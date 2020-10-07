% this code was developed by Marius Pachitariu and Carsen Stringer as part of the software package Suite2p

function S1 = my_conv(S1, sig)

dsnew = size(S1);

S1 = reshape(S1, size(S1,1), []);
dsnew2 = size(S1);

tmax = ceil(4*sig);
dt = -tmax:1:tmax;
gaus = exp( - dt.^2/(2*sig^2));
gaus = gaus'/sum(gaus);

cNorm = filter(gaus, 1, cat(1, ones(dsnew2(1), 1), zeros(tmax,1)));
cNorm = cNorm(1+tmax:end, :);

S1 = filter(gaus, 1, cat(1, S1, zeros([tmax, dsnew2(2)])));
S1(1:tmax, :) = [];
S1 = reshape(S1, dsnew);

S1 = bsxfun(@rdivide, S1, cNorm);

%--------------------------------------------------------------------------%
% my_conv.m                                                                %
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
