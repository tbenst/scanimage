classdef SlmLutGlobal < scanimage.mroi.scanners.slmLut.SlmLut
    properties
        lut = []
    end
    
    properties (Access = private)
        hGI;
    end
    
    methods
        function obj = SlmLutGlobal(lut)
            if nargin > 0
                obj.lut = lut;
            end
        end
    end
    
    methods
        function pixelVals = apply(obj,phis)
            if isempty(obj.lut)
                pixelVals = phis;
                return
            end
            
            phis = single(phis);
            phis = gather(phis);
            phi_size = size(phis);
            
            phis = phis(:);
            lutmax = 2*pi;
            phis = phis - lutmax*floor(phis./lutmax); % mod is slower than this
            pixelVals = obj.hGI(phis);
            pixelVals = reshape(pixelVals,phi_size);
        end
        
        function plot(obj)            
            hFig = figure();
            hAx = axes('Parent',hFig,'Box','on');
            plot(hAx,obj.lut(:,1),obj.lut(:,2));
            hAx.XTick = min(obj.lut(:,1)):(.25*pi):max(obj.lut(:,1));
            
            l = arrayfun(@(v){sprintf('%g\\pi',v)}, round(hAx.XTick/pi,2));
            l(obj.lut(:,1) == 0) = {'0'};
            hAx.XTickLabel = strrep(l,'1\pi','\pi');
            
            hAx.XLim = [min(obj.lut(:,1)) max(obj.lut(:,1))];
            hAx.YLim = [0 max(obj.lut(:,2))*1.2];
            title(hAx,sprintf('SLM Lut at %.1fnm',obj.wavelength_um*1e3));
            xlabel(hAx,'Phase');
            ylabel(hAx,'Pixel Value');
            grid(hAx,'on');
        end
    end
    
    methods (Access = protected)
        function s = saveInternal(obj)
            s = struct();
            s.lut = gather(obj.lut);
        end
        
        function loadInternal(obj,s)
            fields = fieldnames(s);
            for idx = 1:numel(fields)
                field = fields{idx};
                try
                    obj.(field) = s.(field);
                catch ME
                    most.ErrorHandler.logAndReportError(ME);
                end
            end
        end
        
        function updateInterpolant(obj)
            if isempty(obj.lut)
                obj.hGI = [];
            else
                % about twice as fast as interp1
                obj.hGI = griddedInterpolant(obj.lut(:,1),obj.lut(:,2),'linear','nearest');
            end
        end
    end
    
    methods
        function set.lut(obj,val)
            validateattributes(val,{'numeric'},{'ncols',2,'nonnan','finite'});
            assert(issorted(val(:,1)));
            validateattributes(val(:,1),{'numeric'},{'nonnegative','<=',2*pi*1.01});    
            obj.lut = single(val);
            obj.updateInterpolant();
        end
    end
end


%--------------------------------------------------------------------------%
% SlmLutGlobal.m                                                           %
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
