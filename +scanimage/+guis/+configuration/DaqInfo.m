classdef DaqInfo < handle
    properties
        deviceName
        numAOs = 0;
        numAIs = 0;
        numPFIs = 0;
        numPorts = 0;
        portNumLines = 0;
        ao = [];
        ai = [];
        productCategory;
        isXSer = false;
        busType = [];
        simulated = false;
        simultaneousSampling = [];
        maxSingleChannelRate = [];
        maxMultiChannelRate = [];
        pxiNum = NaN;
        allAOs = {};
        allAIs = {};
        pfi = {};
        lines = {};
        olines = {};
        ilines = {};
        port = [];
    end
    
    methods (Static)        
        function obj = fromDaqmxDev(deviceName)
            obj = scanimage.guis.configuration.DaqInfo;
            
            hDaqSys = dabs.ni.daqmx.System;
            hDev = dabs.ni.daqmx.Device(deviceName);
            
            obj.deviceName = deviceName;
            
            obj.productCategory = hDev.productCategory;
            obj.isXSer = strcmp(obj.productCategory,'DAQmx_Val_XSeriesDAQ');
            obj.busType = get(hDev,'busType');
            obj.simulated = get(hDev,'isSimulated');
            
            warnstat = warning('off');
            try
                obj.simultaneousSampling = get(hDev,'AISimultaneousSamplingSupported');
            catch
                obj.simultaneousSampling = false;
            end
            if isempty(obj.simultaneousSampling)
                obj.simultaneousSampling = false;
            end
            
            try
                obj.maxSingleChannelRate = get(hDev,'AIMaxSingleChanRate');
            catch
                obj.maxSingleChannelRate = 0;
            end
            if isempty(obj.maxSingleChannelRate)
                obj.maxSingleChannelRate = 0;
            end
            
            try
                obj.maxMultiChannelRate = get(hDev,'AIMaxMultiChanRate');
            catch
                obj.maxMultiChannelRate = 0;
            end
            if isempty(obj.maxMultiChannelRate)
                obj.maxMultiChannelRate = 0;
            end
            
            
            if strncmp(obj.busType,'DAQmx_Val_PXI',13)
                obj.pxiNum = get(hDev,'PXIChassisNum');
                if obj.pxiNum == 2^32-1
                    obj.pxiNum = 1;
                end
            else
                obj.pxiNum = nan;
            end
            if isempty(obj.pxiNum)
                obj.pxiNum = nan;
            end
            
            warning(warnstat);

            astr = struct();
            astr.users = {};
            astr.bufferedUsers = {};
            
            [r, a] = hDaqSys.apiCall('DAQmxGetDevAOPhysicalChans',deviceName,blanks(5000),5000);
            obj.numAOs = numel(strsplit(a,','));
            obj.ao = repmat(astr,1,obj.numAOs);
            
            [r, a] = hDaqSys.apiCall('DAQmxGetDevAIPhysicalChans',deviceName,blanks(5000),5000);
            obj.numAIs = numel(strsplit(a,','));
            obj.ai = repmat(astr,1,obj.numAIs);
            
            obj.allAOs = arrayfun(@(x)strcat('AO',num2str(x)),0:obj.numAOs-1,'uniformoutput',false);
            obj.allAIs = arrayfun(@(x)strcat('AI',num2str(x)),0:obj.numAIs-1,'uniformoutput',false);
            
            %still dont know how to actually determine number of PFIs
            obj.numPFIs = 16;
            obj.pfi = arrayfun(@(x)sprintf('PFI%d',x),0:(obj.numPFIs-1),'UniformOutput',false);
            
            [r, a] = hDaqSys.apiCall('DAQmxGetDevDIPorts',deviceName,blanks(5000),5000);
            obj.numPorts = numel(strsplit(a,','));
            
            [r, a] = hDaqSys.apiCall('DAQmxGetDevDILines',deviceName,blanks(5000),5000);
            lines = cellfun(@(s)s(length(deviceName)+2:end),strtrim(strsplit(a,',')),'uniformoutput',false)';
            obj.lines = lines;
            obj.ilines = lines;
            obj.olines = lines;
            
            for j = 1:numel(lines)
                ls = strfind(lines{j},'port');
                le = strfind(lines{j}(ls:end),'/');
                prt = str2double(lines{j}(ls+4:ls+le-2))+1;
                
                ls = strfind(lines{j},'line');
                ln = str2double(lines{j}(ls+4:end))+1;
                
                if numel(obj.portNumLines) < prt || isempty(obj.portNumLines(prt))
                    obj.portNumLines(prt) = ln;
                else
                    obj.portNumLines(prt) = max(ln,obj.portNumLines(prt));
                end
            end
        end
        
        function obj = fromVDaq(deviceName)
            devNum = regexp('vDAQ0','(?<=^vDAQ)[0-9]+$','match','once');
            assert(~isempty(devNum),'Incorrect deviceName: %s',deviceName);
            
            devNum = str2double(devNum);
            
            s = dabs.vidrio.rdi.Device.getDeviceInfo(devNum);
            if s.hardwareRevision
                numAOs = 12;
                numAIs = 12;
                digBankNumTerms = [8 8 8 8];
                ibanks = [1 2 3];
                obanks = [1 2 4];
            else
                numAOs = 5;
                numAIs = 4;
                digBankNumTerms = [8 8 8];
                ibanks = [1 2];
                obanks = [1 3];
            end
            
            numDigbanks = numel(digBankNumTerms);
            bankDigs = arrayfun(@(bnk,numTerms){arrayfun(@(trm){sprintf('D%d.%d',bnk,trm)},0:(numTerms-1))},0:(numDigbanks-1),digBankNumTerms);
            
            obj = scanimage.guis.configuration.DaqInfo;
            obj.deviceName = deviceName;
            obj.productCategory = 'vDAQ';
            obj.numAOs = numAOs;
            obj.numAIs = numAIs;
            obj.portNumLines = digBankNumTerms;
            obj.numPorts = numel(obj.portNumLines);
            obj.allAOs = arrayfun(@(x){strcat('AO',num2str(x))},0:obj.numAOs-1);
            obj.allAIs = arrayfun(@(x){strcat('AI',num2str(x))},0:obj.numAIs-1);
            obj.lines = horzcat(bankDigs{:})';
            obj.ilines = horzcat(bankDigs{ibanks})';
            obj.olines = horzcat(bankDigs{obanks})';
            obj.simulated = false;
        end
        
        function obj = simulatedVDaq(deviceName)
            devNum = regexp('vDAQ0','(?<=^vDAQ)[0-9]+$','match','once');
            assert(~isempty(devNum),'Incorrect deviceName: %s',deviceName);
            
            digBankNumTerms = [8 8 8 8];
            numDigbanks = numel(digBankNumTerms);
            ibanks = [1 2 3];
            obanks = [1 2 4];
            bankDigs = arrayfun(@(bnk,numTerms){arrayfun(@(trm){sprintf('D%d.%d',bnk,trm)},0:(numTerms-1))},0:(numDigbanks-1),digBankNumTerms);
            
            obj = scanimage.guis.configuration.DaqInfo;
            obj.deviceName = deviceName;
            obj.productCategory = 'vDAQ';
            obj.numAOs = 12;
            obj.numAIs = 12;
            obj.portNumLines = digBankNumTerms;
            obj.numPorts = numel(obj.portNumLines);
            obj.allAOs = arrayfun(@(x){strcat('AO',num2str(x))},0:obj.numAOs-1);
            obj.allAIs = arrayfun(@(x){strcat('AI',num2str(x))},0:obj.numAIs-1);
            obj.lines = horzcat(bankDigs{:})';
            obj.ilines = horzcat(bankDigs{ibanks})';
            obj.olines = horzcat(bankDigs{obanks})';
            obj.simulated = true;
        end
    end
end



%--------------------------------------------------------------------------%
% DaqInfo.m                                                                %
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
