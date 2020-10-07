function sendSupportReport()
    filePath = fullfile(tempdir(),'SIReport.zip');
    try
        scanimage.util.generateSIReport(false,filePath);
    catch ME
        message = sprintf('Failed to generate support report:\n%s',ME.message);
        msgbox(message,'Error','error');
        rethrow(ME);
    end
    
    hLM = scanimage.util.private.LM();
    collect = hLM.collectUsageData;
    hLM.collectUsageData = true;
    success = hLM.log(filePath,'Support report submitted.');
    hLM.collectUsageData = collect;
    
    if ~success
        msgbox('Failed to send support report','Error','error');
        error('Failed to send support report.');
    end
end

%--------------------------------------------------------------------------%
% sendSupportReport.m                                                      %
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
