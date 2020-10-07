function alignedRoiData = alignZRoiData(roiData)
    % roiData validation
    validateattributes(roiData,{'scanimage.mroi.RoiData'},{'vector'});
    assert(numel(unique([roiData.hRoi]))==1,'All roiData must reference the same roi for alignment');
    assert(numel(roiData(1).channels) == 1 &&...
        all(cellfun(@(ch)isequal(ch,roiData(1).channels),{roiData.channels})),...
        'The channels for all roiData need to be the same. There can only be one channel.');
    assert(all(cellfun(@(zs)isequal(zs,roiData(1).zs),{roiData.zs})),...
        'The zs for all roiData need to be the same for alignment');

    if isscalar(roiData)
        alignedRoiData = roiData; % Nothing to do here
        return
    end

    roiName = roiData(1).hRoi.name;
    cancel = false;
    hWb = waitbar(0,sprintf('Aligning Z Stacks for Roi %s...',roiName), ...
        'Name', 'Z-Stack Alignment',...
        'CreateCancelBtn',@(src,evt)cancelFcn(true),...
        'CloseRequestFcn',@(src,evt)cancelFcn(true));

    try
        % assume referenceRoiData is an array of roiData, containing
        % multiple repetitions
        % roiData.imageData{chidx}{zidx}
        chIdx = 1; % channel index
        refIms = arrayfun(@(rD)cat(3,rD.imageData{chIdx}{:}),roiData,'UniformOutput',false);
        refIms = cat(4,refIms{:}); % 4D array [resX,resY,slice,volume]
        refIms = single(refIms);

        % save std and mean
        for zIdx = 1:size(refIms,3)
            refIm = refIms(:,:,zIdx,:);
            expectedStd(1,1,zIdx)  = std(refIm(:));  %#ok<AGROW>
            expectedMean(1,1,zIdx) = mean(refIm(:)); %#ok<AGROW>
        end
        
        % perform alignment
        Z = scanimage.components.motionEstimators.util.alignZStacks(refIms,@progressFcn,@cancelFcn);
        
        % restore std and mean
        Z = bsxfun(@times,Z,expectedStd./std(reshape(Z,[],1,size(Z,3))));
        Z = bsxfun(@plus,Z,expectedMean-mean(reshape(Z,[],1,size(Z,3))));

        alignedRoiData = roiData(1).copy();
        alignedRoiData.imageData{chIdx} = mat2cell(Z,size(Z,1),size(Z,2),ones(1,size(Z,3)));
        
    catch ME
        most.idioms.safeDeleteObj(hWb);
        rethrow(ME);
    end
    
    most.idioms.safeDeleteObj(hWb);
    
    function cancel_ = cancelFcn(varargin)
        if nargin > 0
            cancel = varargin{1};
        end
        cancel_ = cancel;
    end

    function progressFcn(progress)
        if ~isempty(hWb) && isvalid(hWb)
            waitbar(progress,hWb);
        end
    end
end

%--------------------------------------------------------------------------%
% alignZRoiData.m                                                          %
% Copyright © 2020 Vidrio Technologies, LLC                                %
%                                                                          %
% ScanImage is licensed under the Apache License, Version 2.0              %
% (the "License"); you may not use any files contained within the          %
% ScanImage release  except in compliance with the License.                %
% You may obtain a copy of the License at                                  %
% http://www.apache.org/licenses/LICENSE-2.0                               %
%                                                                          %
% Unless required by applicable law or agreed to in writing, software      %
% distributed under the License is distributed on an "AS IS" BASIS,        %
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. %
% See the License for the specific language governing permissions and      %
% limitations under the License.                                           %
%--------------------------------------------------------------------------%
