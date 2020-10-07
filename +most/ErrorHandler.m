classdef ErrorHandler < handle
    %% Static methods
    methods (Static)
        function varargout = reportError(ME,varargin)
            varargout = cell(1,nargout);
            [varargout{:}] = most.ErrorHandler.printError(ME,varargin{:});
            
            hHandler = most.ErrorHandler();
            hHandler.logErrorPrivate(ME);
        end
        
        function varargout = printError(ME,includestack,includelinks)
            %REPORTERROR Display, or return, report of error to command-line in error color (i.e. red), without throwing error
            %% SYNTAX
            %   function reportError(ME,printstack)
            %   function errString = reportError(ME,includestack)
            %       includestack: <optional> true(default)/false include stack in errstring
            %       errString: 'Safe' error report string, suited for use in fprintf statements by caller
            %
            %% NOTES
            %   Generally suited as a safe-in-all-cases display of the string generated by the MException getReport() method
            %   Particularly suited for:
            %       Use in callback functions which cannot generate true exceptions
            %       Error messages/reports that contan filenames/paths which can confuse frintf
            %
            
            if nargin < 2 || isempty(includestack)
                includestack = true;
            end
            
            if nargin < 3 || isempty(includelinks) || ~includelinks
                includelinks = 'off';
            else
                includelinks = 'on';
            end
            
            if includestack
                reporttype = 'extended';
            else
                reporttype = 'basic';
            end
            
            if ~isa(ME,'MException')
                ME = most.ErrorHandler.getError(ME);
            end
            
            errString = ME.getReport(reporttype,'hyperlinks',includelinks);
            errString = strrep(errString,'\','\\'); %Don't recognize any escape characters
            errString = strrep(errString,'%','%%'); %Don't recognize any formatting characters
            
            if nargout
                varargout = {errString};
            else
                most.idioms.dispError(errString);
            end
        end
        
        function MException(varargin)
            try
                MException(varargin{:}); % this includes the ErrorHandler.error function in the stack
            catch ME
                try
                    ME.throwAsCaller(); % remove one layer of the stack
                catch ME
                    hHandler = most.ErrorHandler();
                    ME = hHandler.logErrorPrivate(ME);
                    throwAsCaller(ME);
                end
            end
        end
        
        function error(varargin)
            try
                error(varargin{:}); % this includes the ErrorHandler.error function in the stack
            catch ME
                try
                    ME.throwAsCaller(); % remove one layer of the stack
                catch ME
                    hHandler = most.ErrorHandler();
                    ME = hHandler.logErrorPrivate(ME);
                    throwAsCaller(ME);
                end
            end
        end
        
        function rethrow(ME)
            hHandler = most.ErrorHandler();
            ME = hHandler.logErrorPrivate(ME);
            rethrow(ME);
        end
        
        function throw(ME)
            hHandler = most.ErrorHandler();
            ME = hHandler.logErrorPrivate(ME);
            throw(ME);
        end
        
        function throwAsCaller(ME)
            try
                throwAsCaller(ME); % removes one layer from the stack
            catch ME
                hHandler = most.ErrorHandler();
                ME = hHandler.logErrorPrivate(ME);
                rethrow(ME);
            end
        end
        
        function ME = logAndReportError(varargin)
            % logAndReportError(ME,message,level)
            %     OR
            % logAndReportError('format string %s %d',arg1,argN);
            
            if ~isa(varargin{1},'MException')
                try
                    error(varargin{:})
                catch ME
                    try
                        ME.throwAsCaller();
                    catch ME
                        most.ErrorHandler.logAndReportError(ME,ME.message);
                        return;
                    end
                end
            else
                ME = varargin{1};
                if nargin < 2 || isempty(varargin{2})
                    message = ['Error occurred: ' ME.message];
                else
                    message = varargin{2};
                end
                if nargin < 3 || isempty(varargin{3})
                    level = 2;
                else
                    level = varargin{3};
                end
            end
            
            ME = most.ErrorHandler.logError(ME);
            
            hHandler = most.ErrorHandler();            
            if hHandler.verbose
                most.ErrorHandler.printError(ME);
            else
                spprtlink = '<a href ="matlab: scanimage.util.generateSIReport(0);">support report</a>';
                errorReport = ME.getReport('extended');
                errorReport = mat2str(unicode2native(errorReport,'UTF-8'));

                errlink = ['<a href ="matlab:fprintf(2,''\n%s\n'', native2unicode(' errorReport ',''UTF-8''));">View detailed error information</a>.'];
                clclink = ['<a href ="matlab:clc">Clear command window</a>.'];

                switch level
                    case 2
                        fprintf(2,'%s\nIf this problem persists contact support and include a %s. %s %s\n\n', message, spprtlink, clclink, errlink);
                    case 1
                        most.idioms.warn('%s\nIf this problem persists contact support and include a %s. %s %s\n', message, spprtlink, clclink, errlink);
                end
            end
        end
        
        function ME = logError(ME)
            hHandler = most.ErrorHandler();
            ME = hHandler.logErrorPrivate(ME);
        end
        
        function resetHistory()
            hHandler = most.ErrorHandler();
            hHandler.resetHistoryPrivate();
        end
        
        function startLogging(logFileName)
            hHandler = most.ErrorHandler();
            hHandler.startLoggingPrivate(logFileName);
        end
        
        function stopLogging()
            hHandler = most.ErrorHandler();
            hHandler.stopLoggingPrivate();
        end
        
        function [MEs,timestamps] = errorHistory()
            hHandler = most.ErrorHandler();
            MEs = hHandler.errorHistory_private;
            timestamps = hHandler.errorTimestamps_private;
        end
        
        function varargout = tryCatch(fcnHdl,varargin)
            try
                [varargout{1:nargout}] = fcnHdl(varargin{:});
            catch ME
                most.ErrorHandler.throwAsCaller(ME);
            end
        end
        
        function setHistoryLength(val)
            hHandler = most.ErrorHandler();
            hHandler.historyLength = val;
        end
        
        function setErrorCallback(val)
            hHandler = most.ErrorHandler();
            hHandler.errorCallback = val;
        end
        
        function setVerbose(val)
            hHandler = most.ErrorHandler();
            hHandler.verbose = val;
        end
        
        function uuid = getMEUuid(ME)
            uuid = '';
            if strcmpi(ME.identifier,'ErrorHandler:uuid')
                uuid = ME.message;
                [~,tokens] = regexpi(uuid,'ErrorHandler\: (.*)$','match','tokens');
                uuid = tokens{1}{1};
            else
                for idx = 1:length(ME.cause)
                    ME_ = ME.cause{idx};
                    uuid = most.ErrorHandler.getMEUuid(ME_);
                    if ~isempty(uuid)
                        return
                    end
                end
            end
        end
        
        function [ME,timestamp] = getError(uuid)
            [MEs,timestamps] = most.ErrorHandler.errorHistory();
            uuids = cellfun(@(me)most.ErrorHandler.getMEUuid(me),MEs,'UniformOutput',false);
            mask = strcmpi(uuid,uuids);
            assert(any(mask), 'Requested error not found.');
            ME = MEs{find(mask,1)};
            timestamp = timestamps(find(mask,1));
        end
        
        function h = addCatchingListener(varargin)
            cb = varargin{end};
            varargin{end} = @(varargin)most.ErrorHandler.catchingDispatch(cb,varargin);
            h = addlistener(varargin{:});
        end
        
        function catchingDispatch(cb,args)
            try
                cb(args{:});
            catch ME
                msg = sprintf('Error occured while handling an event. The last command may not have produced the expected behavior.\nError message: %s', ME.message);
                most.ErrorHandler.logAndReportError(ME, msg, 1);
            end
        end
    end
    
    %% Properties
    properties (SetAccess = private)
        historyLength = 100;
        errorHistory_private = {}; % this needs to be a cell array because it can contain MException AND matlab.exception.JavaException (thrown for instance by MMC)
        errorTimestamps_private = [];
        errorCallback = [];
        verbose = false;
    end
    
    properties (Access = private)
        hFile
        lastWrittenNBytes = 0;
    end
    
    methods
        function obj = ErrorHandler()
            obj = Singleton(obj);
        end
        
        function delete(obj)
            obj.stopLoggingPrivate();
        end
    end
    
    %% Private Methods
    methods (Access = private)
        function startLoggingPrivate(obj,logFileName)
            validateattributes(logFileName,{'char'},{'row'});
            
            obj.stopLogging();
            
            if exist(logFileName,'file')
                % open existing file, seek to end of file
                [hFile_,errmsg] = fopen(logFileName,'r+'); % we cannot use 'A' because then fseek does not work
                fseek(hFile_,0,'eof');
            else
                % open new file
                [hFile_,errmsg] = fopen(logFileName,'w+');
            end
            assert(hFile_ > 0,'Could not open log file %s',logFileName);
            
            obj.hFile = hFile_;
        end
        
        function stopLoggingPrivate(obj)
            if ~isempty(obj.hFile)
                fclose(obj.hFile);
                obj.hFile = [];
            end
        end
        
        function resetHistoryPrivate(obj)
            obj.errorHistory_private = {};
            obj.errorTimestamps_private = [];
        end
        
        function ME = logErrorPrivate(obj,ME)
            [replace,ME] = checkReplace(ME);
            
            if replace
                obj.errorHistory_private{end} = ME;
                timestamp = obj.errorTimestamps_private(end);
            else
                [ME,timestamp] = appendErrorHistory(ME);
            end
            
            
            if ~isempty(obj.hFile)
                errString = ME.getReport('extended','hyperlinks','off');
                
                out = sprintf('========== %s ==========',datestr(timestamp,'yyyy-mm-dd HH:MM:SS:FFF'));
                out = sprintf('%s\n%s\n\n',out,errString);
                
                if replace
                    fseek(obj.hFile,-obj.lastWrittenNBytes,0);
                end
                
                obj.lastWrittenNBytes = fwrite(obj.hFile,char(out));
            end
            
            if ~isempty(obj.errorCallback)
                try
                    obj.errorCallback(ME);
                catch
                end
            end
            
            function [ME,timestamp] = appendErrorHistory(ME)
                timestamp = now();
                
                if isempty(obj.errorHistory_private)
                    obj.errorHistory_private = {ME};
                    obj.errorTimestamps_private = timestamp;
                elseif numel(obj.errorHistory_private) > obj.historyLength                    
                    obj.errorHistory_private(end+1-obj.historyLength:end) = [];
                    obj.errorHistory_private = circshift(obj.errorHistory_private,-1,2);
                    obj.errorHistory_private{end} = ME;
                    
                    obj.errorTimestamps_private(end+1-obj.historyLength:end) = [];
                    obj.errorTimestamps_private = circshift(obj.errorTimestamps_private,-1,2);
                    obj.errorTimestamps_private(end) = timestamp;
                elseif numel(obj.errorHistory_private) < obj.historyLength
                    obj.errorHistory_private{end+1} = ME;
                    obj.errorTimestamps_private = [obj.errorTimestamps_private timestamp];
                else
                    obj.errorHistory_private = circshift(obj.errorHistory_private,-1,2);
                    obj.errorHistory_private{end} = ME;
                    
                    obj.errorTimestamps_private = circshift(obj.errorTimestamps_private,-1,2);
                    obj.errorTimestamps_private(end) = timestamp;
                end
            end
            
            function [replace,ME] = checkReplace(ME)
                uuid = obj.getMEUuid(ME);
                if isempty(uuid)
                    ME = MEaddUuid(ME);
                    replace = false;
                else
                    replace = true;
                end
            end
        end
    end
    
    methods
        function set.verbose(obj,val)
            validateattributes(val,{'numeric','logical'},{'binary','scalar'});
            obj.verbose = logical(val);
        end
        
        function set.historyLength(obj,val)
            validateattributes(val,{'numeric'},{'integer','positive','nonnan','finite','real'});
            obj.historyLength = val;
        end
        
        function set.errorCallback(obj,val)
            if ~isempty(val)
                validateattributes(val,{'function_handle'},{'scalar'});
            else
                val = [];
            end
            
            obj.errorCallback = val;
        end
    end
end

function obj = Singleton(obj)
    persistent singleton

    if isempty(singleton) || ~isvalid(singleton)
        singleton = obj;
    else
        delete(obj);
        obj = singleton;
    end
end

function ME = MEaddUuid(ME)
    ME_ = MException('ErrorHandler:uuid',sprintf('%s - Caught by ErrorHandler: %s',datestr(clock),most.util.generateUUID()));
    ME = addCause(ME,ME_);
end

%--------------------------------------------------------------------------%
% ErrorHandler.m                                                           %
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
