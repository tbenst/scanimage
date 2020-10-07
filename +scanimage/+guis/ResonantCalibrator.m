classdef ResonantCalibrator < most.Gui
    
    properties (Hidden)
        hCalPlot;
        hCalPlotPt;
        
        hAx;
        hBottomCtls;
        cbEnable;
        
        hS2d;
        
        hVisListner;
        hS2dListner;
        hResAmpListner;
    end
    
    %% Lifecycle
    methods
        function obj = ResonantCalibrator(hModel, hController)
            %% main figure
            if nargin < 1
                hModel = [];
            end
            
            if nargin < 2
                hController = [];
            end
            
            obj = obj@most.Gui(hModel, hController, [460 320]);
            set(obj.hFig,'Name','Resonant FOV Calibration');
            hmain=most.idioms.uiflowcontainer('Parent',obj.hFig,'FlowDirection','TopDown');
            up = uipanel('Parent',hmain,'bordertype','none');
            obj.hAx = axes('Parent',up,'FontSize',12,'FontWeight','Bold');
            obj.hCalPlot = plot(nan, nan,'k.-','Parent',obj.hAx,'MarkerSize',20,'LineWidth',2);
            hold(obj.hAx,'on');
            obj.hCalPlotPt = plot(nan, nan,'ro','MarkerSize',10,'LineWidth',2,'Parent',obj.hAx);
            
            xlabel(obj.hAx,'Resonant Scan Amplitude (% of Max)','FontWeight','Bold');
            xlim(obj.hAx,[-5 105]);
            
            ylabel(obj.hAx,'Command Voltage (V)','FontWeight','Bold');
            ylim(obj.hAx,[-.2 5.2]);
            
            grid(obj.hAx,'on');
            
            bottomContainer = most.idioms.uiflowcontainer('Parent',hmain,'FlowDirection','LeftToRight');
            set(bottomContainer,'HeightLimits',[30 30]);
            obj.cbEnable = most.gui.uicontrol('parent',bottomContainer,'style','checkbox','string','Enable');
            
            b1 = uicontrol('parent',bottomContainer,'style','pushbutton','Callback',@(src,evt)obj.clearCal(),'string','Reset');
            b2 = uicontrol('parent',bottomContainer,'style','pushbutton','Callback',@(src,evt)obj.createCalPoint(),'string','Add Point');
            b3 = uicontrol('parent',bottomContainer,'style','pushbutton','Callback',@(src,evt)obj.removeCalPoint(),'string','Del Point');
            
            ad1 = uicontrol('parent',bottomContainer,'style','pushbutton','Callback',@(src,evt)obj.adjustCal(-0.03),'string',char(8650),'FontName','Arial Unicode MS');
            ad2 = uicontrol('parent',bottomContainer,'style','pushbutton','Callback',@(src,evt)obj.adjustCal(-0.005),'string',char(8595),'FontName','Arial Unicode MS');
            ad3 = uicontrol('parent',bottomContainer,'style','pushbutton','Callback',@(src,evt)obj.adjustCal(0.005),'string',char(8593),'FontName','Arial Unicode MS');
            ad4 = uicontrol('parent',bottomContainer,'style','pushbutton','Callback',@(src,evt)obj.adjustCal(0.03),'string',char(8648),'FontName','Arial Unicode MS');
            set([ad1 ad2 ad3 ad4],'WidthLimits',[40 40]);
            
            obj.hBottomCtls = [b1 b2 b3 ad1 ad2 ad3 ad4];
            
            if ~isempty(hModel)
                obj.hS2dListner = most.ErrorHandler.addCatchingListener(obj.hModel,'imagingSystem','PostSet',@obj.scannerChanged);
                obj.hVisListner = most.ErrorHandler.addCatchingListener(obj.hFig,'Visible','PostSet',@obj.updatePlot);
                
                obj.scannerChanged();
            end
        end
        
        function delete(obj)
            delete(obj.hVisListner);
            delete(obj.hS2dListner);
            delete(obj.hResAmpListner);
        end
    end
    
    methods
        function scannerChanged(obj,varargin)
            delete(obj.hResAmpListner);
            
            obj.hS2d = obj.hModel.hScan2D;
            if strcmp(obj.hS2d.scanMode, 'resonant')
                obj.cbEnable.Enable = 'on';
                obj.cbEnable.bindings = {{obj.hS2d 'useNonlinearResonantFov2VoltsCurve' 'value'} {obj.hS2d 'useNonlinearResonantFov2VoltsCurve' 'callback' @obj.updatePlot}};
                obj.hCalPlot.Visible = 'on';
                obj.hCalPlotPt.Visible = 'on';
                obj.hResAmpListner = [most.ErrorHandler.addCatchingListener(obj.hS2d,'resonantScannerOutputVoltsUpdated',@obj.updatePlot)...
                    most.ErrorHandler.addCatchingListener(obj.hModel.hRoiManager,'imagingRoiGroupChanged',@obj.updatePlot)...
                    most.ErrorHandler.addCatchingListener(obj.hModel.hRoiManager,'mroiEnable','PostSet',@obj.updatePlot)];
                obj.hFig.Name = sprintf('Resonant FOV Calibration (%s)', obj.hS2d.name);
            else
                obj.cbEnable.bindings = {};
                obj.cbEnable.Value = 0;
                obj.hCalPlot.Visible = 'off';
                obj.hCalPlotPt.Visible = 'off';
                set(obj.hBottomCtls, 'Enable', 'off');
                obj.cbEnable.Enable = 'off';
                obj.hFig.Name = 'Resonant FOV Calibration';
            end
        end
        
        function updatePlot(obj,varargin)
            if strcmp(obj.hS2d.scanMode, 'resonant') && obj.Visible
                if obj.hModel.hScan2D.useNonlinearResonantFov2VoltsCurve
                    obj.hCalPlot.XData = cell2mat(obj.hModel.hScan2D.resFov2VoltsMap.keys)*100;
                    obj.hCalPlot.YData = cell2mat(obj.hModel.hScan2D.resFov2VoltsMap.values);
                    set(obj.hBottomCtls, 'Enable', 'on');
                else
                    obj.hCalPlot.XData = [0 100];
                    obj.hCalPlot.YData = [0 5];
                    set(obj.hBottomCtls, 'Enable', 'off');
                end
                
                fov = obj.hModel.hScan2D.hCtl.nextResonantFov();
                obj.hCalPlotPt.XData = fov*100;
                obj.hCalPlotPt.YData = obj.hModel.hScan2D.zzzResonantFov2Volts(fov);
            end
        end
        
        function clearCal(obj,varargin)
            obj.hS2d.clearResFov2VoltsCal();
            obj.updatePlot();
        end
        
        function createCalPoint(obj, varargin)
            obj.hS2d.createResFov2VoltsCalPoint();
            obj.updatePlot();
        end
        
        function removeCalPoint(obj, varargin)
            obj.hS2d.removeResFov2VoltsCalPoint();
            obj.updatePlot();
        end
        
        function adjustCal(obj, adj)
            % adjust the voltage of the resonant scanner up or down for the
            % current desired FOV by [adj]%
            fov = obj.hS2d.hCtl.nextResonantFov;
            v = obj.hS2d.zzzResonantFov2Volts(fov);
            v = v * (1+adj);
            obj.hS2d.setResFov2VoltsCalPoint(fov,v);
            obj.updatePlot();
        end
    end
    
    %% prop access
    methods
    end
end


%--------------------------------------------------------------------------%
% ResonantCalibrator.m                                                     %
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
