% Source: https://www.mathworks.com/matlabcentral/fileexchange/45480-connected-component-labeling
%
% Copyright (c) 2014, André Ødegårdstuen
% All rights reserved.
% 
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are
% met:
% 
%     * Redistributions of source code must retain the above copyright
%       notice, this list of conditions and the following disclaimer.
%     * Redistributions in binary form must reproduce the above copyright
%       notice, this list of conditions and the following disclaimer in
%       the documentation and/or other materials provided with the distribution
% 
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
% LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
% CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
% ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
% POSSIBILITY OF SUCH DAMAGE.

function [ labels ] = anodeg_bwlabel( data )
%anodeg_bwlable binary image labeling
% Labels a binary image through 8-point connectivity without the need 
% for any toolboxes. 


[x,y] = size(data);
% expand dataset to avoid crash when searching:
data = [zeros(1,y+2);[zeros(x,1) data zeros(x,1)]];
[x,y] = size(data);

labels = zeros(size(data));
nextlabel = 1;
linked = {};

for i = 2:x                       % for each row
    for j = 2:y-1                 % for each column
        if data(i,j) ~= 0         % not background
            % find binary value of neighbours
            neighboursearch = [data(i-1,j-1), data(i-1,j), data(i-1,j+1),data(i,j-1)];
            % for 4-connectivity, replace with:
%             neighboursearch = [data(i-1,j),data(i,j-1)];
            
            % search for neighbours with binary value 1
            [~,n,neighbours] = find(neighboursearch==1);
            
            % if no neighbour is allready labeled: assign new label
            if isempty(neighbours)
                linked{nextlabel} = nextlabel; %#ok<*AGROW>
                labels(i,j) = nextlabel;
                nextlabel = nextlabel+1;                
            
            % if neighbours is labeled: pick the lowest label and store the
            % connected labels in "linked"
            else
                neighboursearch_label = [labels(i-1,j-1), labels(i-1,j), labels(i-1,j+1),labels(i,j-1)];
                L = neighboursearch_label(n);
                labels(i,j) = min(L);
                for k = 1:length(L)
                    label = L(k);
                    linked{label} = unique([linked{label} L]);
                end                
            end
        end
    end
end

% remove the previous expansion of the image
labels = labels(2:end,2:end-1);


%% join linked areas


% for each link, look through the other links and look for common labels.
% if common labels exist they are linked -> replace both link with the 
% union of the two. Repeat until there is no change in the links.

change2 = 1;
while change2 == 1
    change = 0;
    for i = 1:length(linked)
        for j = 1:length(linked)
            if i ~= j
                if sum(ismember(linked{i},linked{j}))>0 && sum(ismember(linked{i},linked{j})) ~= length(linked{i})
                    change = 1;
                    linked{i} = union(linked{i},linked{j});
                    linked{j} = linked{i};
                end
            end
        end
    end
    
    if change == 0
        change2 = 0;
    end
    
end

% removing redundat links
linked = unique(cellfun(@num2str,linked,'UniformOutput',false));
linked = cellfun(@str2num,linked,'UniformOutput',false);

K = length(linked);
templabels = labels;
labels = zeros(size(labels));

% label linked labels with a single label:
for k = 1:K
    for l = 1:length(linked{k})
        labels(templabels == linked{k}(l)) = k;
    end
end

end

            
            
            


%--------------------------------------------------------------------------%
% anodeg_bwlabel.m                                                         %
% Copyright � 2020 Vidrio Technologies, LLC                                %
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
