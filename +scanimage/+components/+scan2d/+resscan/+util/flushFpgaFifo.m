function success = flushFpgaFifo(fifo,timeout_s)
if nargin < 2 || isempty(timeout_s)
    timeout_s = 5;
end

validateattributes(fifo,{'dabs.ni.rio.NiFIFO'},{'scalar'});
validateattributes(timeout_s,{'numeric'},{'positive','scalar','finite','nonnan','real'});


starttime = tic();
elremaining = 1;

success = false;
while elremaining > 0
    try
        [~,elremaining] = fifo.read(elremaining,0);
    catch ME
        if ~isempty(strfind(ME.message,'-50400')) % filter timeout error
            break
        end
        most.ErrorHandler.logAndReportError(ME);
    end
    if toc(starttime) >= timeout_s
        if nargout < 1
            most.idioms.warn('Could not flush fifo %s within timeout.',fifo.fifoName);
        end
        return
    end
end

success = true;

end

%--------------------------------------------------------------------------%
% flushFpgaFifo.m                                                          %
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
