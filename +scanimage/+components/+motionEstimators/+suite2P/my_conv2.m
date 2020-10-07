% this code was developed by Marius Pachitariu and Carsen Stringer as part of the software package Suite2p

function S1 = my_conv2(S1, sig, varargin)
% takes an extra argument which specifies which dimension to filter on
% extra argument can be a vector with all dimensions that need to be
% smoothed, in which case sig can also be a vector of different smoothing
% constants

[~,~,packageName] = most.idioms.getFunctionInfo();
import([packageName '.*']);

if sig>.25
    idims = 2;
    if ~isempty(varargin)
        idims = varargin{1};
    end
    if numel(idims)>1 && numel(sig)>1
        sigall = sig;
    else
        sigall = repmat(sig, numel(idims), 1);
    end
    
    for i = 1:length(idims)
        sig = sigall(i);
        
        idim = idims(i);
        Nd = ndims(S1);
        
        S1 = permute(S1, [idim 1:idim-1 idim+1:Nd]);

        S1 = my_conv(S1, sig);
%         dsnew = size(S1);
%         
%         S1 = reshape(S1, size(S1,1), []);
%         dsnew2 = size(S1);
%                 
%         tmax = ceil(4*sig);
%         dt = -tmax:1:tmax;
%         gaus = exp( - dt.^2/(2*sig^2));
%         gaus = gaus'/sum(gaus);
%                 
%         cNorm = filter(gaus, 1, cat(1, ones(dsnew2(1), 1), zeros(tmax,1)));
%         cNorm = cNorm(1+tmax:end, :);
%         
%         S1 = filter(gaus, 1, cat(1, S1, zeros([tmax, dsnew2(2)])));
%         S1(1:tmax, :) = [];
%         S1 = reshape(S1, dsnew);
%         
%         S1 = bsxfun(@rdivide, S1, cNorm);
        
        S1 = permute(S1, [2:idim 1 idim+1:Nd]);
    end
end

%--------------------------------------------------------------------------%
% my_conv2.m                                                               %
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
