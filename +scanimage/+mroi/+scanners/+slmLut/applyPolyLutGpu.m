function out = applyPolyLutGpu(phi,lut)
    phi = mod(phi,2*pi);
    
    if isempty(lut)
        out = phi;
        return
    end

    degree = single(size(lut,3)-1);
    
    idx = uint32(1:size(lut,1))';
    jdx = uint32(1:size(lut,2));
    
    out = arrayfun(@apply_,phi,idx,jdx,degree);

    function out = apply_(phi,idx,jdx,degree)
        out = lut(idx,jdx,1);
        
        d = single(1);
        while d<=degree
            d_inc = d+1;
            f = lut(idx,jdx,uint32(d_inc));
            out = out + f * phi ^ d;
            d = d_inc;
        end
    end
end

%--------------------------------------------------------------------------%
% applyPolyLutGpu.m                                                        %
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
