classdef  MotorControls < most.Gui    
    %% GUI PROPERTIES
    properties (SetAccess = protected,SetObservable,Hidden)
        hListeners = event.listener.empty(1,0);
        hAx;
        hPatchFastZLimits;
        hLineFocus;
        hLineFocusMarker;
        hTextFocus;
        
        hPmCoordinateSystem
        hCSDisplay
    end
    
    properties (SetObservable)
        xyIncrement = 10;
        zIncrement = 10;
        fastZIncrement = 10;
    end
    
    %% LIFECYCLE
    methods
        function obj = MotorControls(hModel, hController)
            if nargin < 1
                hModel = [];
            end
            
            if nargin < 2
                hController = [];
            end
            
            obj = obj@most.Gui(hModel, hController, [360 300], 'pixels');
            obj.hFig.Name = 'MOTOR CONTROLS';
            obj.hFig.WindowScrollWheelFcn = @obj.scroll;
            obj.hFig.KeyPressFcn = @obj.keyPressed;
            obj.hFig.Resize = 'off';
            
            obj.initGUI();
            
            obj.hListeners(end+1) = most.ErrorHandler.addCatchingListener(obj.hModel.hMotors,'motorPosition','PostSet',@obj.update);
            obj.hListeners(end+1) = most.ErrorHandler.addCatchingListener(obj.hModel.hCoordinateSystems.hCSFocus,'changed',@obj.update);
            obj.hListeners(end+1) = most.ErrorHandler.addCatchingListener(obj.hModel.hMotors,'errorMsg','PostSet',@obj.errorStatusChanged);
            obj.hListeners(end+1) = most.ErrorHandler.addCatchingListener(obj.hModel.hMotors,'simulatedAxes','PostSet',@obj.simulatedAxesChanged);
            
            obj.changeCoordinateSystem();
            
            obj.update();
            obj.errorStatusChanged();
            obj.simulatedAxesChanged();
        end
        
        function delete(obj)
            most.idioms.safeDeleteObj(obj.hListeners);
        end
    end
    
    methods
        function initGUI(obj)
            hFlowMain = most.gui.uiflowcontainer('Parent', obj.hFig,'FlowDirection','LeftToRight');
                hFlowAx = most.gui.uiflowcontainer('Parent', hFlowMain,'FlowDirection','TopDown');
                hFlowMotor = most.gui.uiflowcontainer('Parent', hFlowMain,'FlowDirection','TopDown');
                    set(hFlowMotor,'WidthLimits',[155,155]);
                hFlowFastZ = most.gui.uiflowcontainer('Parent', hFlowMain,'FlowDirection','TopDown');
                    set(hFlowFastZ,'WidthLimits',[70,70]);
                
            makeAxis(hFlowAx);
            makeMotorsPanel(hFlowMotor);
            makeFastZPanel(hFlowFastZ);
            
            function makeAxis(hParent)                
                obj.hAx = axes('Parent',hParent,'XTick',[],'YDir','reverse','YGrid','on','ButtonDownFcn',@obj.dragAxes);
                obj.hAx.OuterPosition = [0.05 0 0.9 1];
                obj.hAx.XLim = [0 1];
                obj.hAx.XTick = [0 0.5 1];
                obj.hAx.XTickLabel = {'FastZ  ' '[um]' ''};
                title(obj.hAx,'Z-Focus','FontWeight','normal');
                box(obj.hAx,'on');
                
                %ylabel(obj.hAx,'Z Reference Space [um]');
                obj.hPatchFastZLimits = patch('Parent',obj.hAx,'Faces',[],'Vertices',[],'FaceColor',[0 0 0],'FaceAlpha',0.2,'LineStyle','none');
                obj.hLineFocus = line('Parent',obj.hAx,'XData',[],'YData',[],'LineStyle','-','Color',[1 0 0],'LineWidth',0.5,'ButtonDownFcn',@obj.dragFocus);
                obj.hLineFocusMarker = line('Parent',obj.hAx,'XData',[],'YData',[],'LineStyle','none','Marker','*','MarkerSize',8,'Color',[1 0 0],'LineWidth',1,'ButtonDownFcn',@obj.dragFocus);
                obj.hTextFocus = text('Parent',obj.hAx,'String','','Position',[0 0],'HorizontalAlignment','center','VerticalAlignment','top','VerticalAlignment','bottom','Interpreter','tex','PickableParts','none','HitTest','off');
                
                if yyaxisAvailable()
                    yyaxis(obj.hAx,'right');
                    %ylabel(obj.hAx,'Z Sample [um]');
                    obj.hAx.YAxis(1).Color = [0 0 0];
                    obj.hAx.YAxis(2).Color = [0 0 0];
                    obj.hAx.YAxis(2).Direction = 'reverse';
                    obj.hAx.XTickLabel{3} = '   Sample';
                end
            end
                
            function makeMotorsPanel(hParent)
                hPanel = most.gui.uipanel('Title','Motors','Parent',hParent);
                
                csOptions = {'Sample','Stage','Raw Motor'};
                obj.hPmCoordinateSystem = obj.addUiControl('Parent',hPanel,'String',csOptions,'style','popupmenu','Callback',@obj.changeCoordinateSystem,'Tag','pmCoordinateSystem','RelPosition', [15 42 90 20],'TooltipString','Select coordinate system for XYZ axes display');
                obj.addUiControl('Parent',hPanel,'String','Zero All','style','pushbutton','Tag','pbZeroAll','RelPosition', [85 149 60 20],'Enable','on','Callback',@(varargin)obj.zeroSample([1 2 3]),'TooltipString','Establish relative zero point for all axes');
                obj.addUiControl('Parent',hPanel,'String','Clear Zeros','style','pushbutton','Tag','pbClearZero','RelPosition', [14 149 70 20],'Enable','on','Callback',@(varargin)obj.clearZero(),'TooltipString','Reset relative zero point for all axes');
                obj.addUiControl('Parent',hPanel,'String','Query Position','Callback',@obj.queryPosition,'style','pushbutton','Tag','pbQueryPosition','RelPosition', [15 62 90 20],'Enable','on','TooltipString','Query motors for position');
                
                obj.addUiControl('Parent',hPanel,'String','X','style','text','Tag','lbXPos','HorizontalAlignment','right','RelPosition', [1 82 10 15],'FontWeight','bold');
                obj.addUiControl('Parent',hPanel,'String','etXPos','style','edit','Callback',@obj.changePosition,'Tag','etXPos','RelPosition', [15 83 90 20]);
                obj.addUiControl('Parent',hPanel,'String','Zero','style','pushbutton','Tag','pbZeroX','RelPosition', [106 83 40 20],'Enable','on','Callback',@(varargin)obj.zeroSample(1),'TooltipString','Establish relative zero point for X-axis');
                
                obj.addUiControl('Parent',hPanel,'String','Y','style','text','Tag','lbYPos','HorizontalAlignment','right','RelPosition', [1 104 10 15],'FontWeight','bold');
                obj.addUiControl('Parent',hPanel,'String','etYPos','style','edit','Callback',@obj.changePosition,'Tag','etYPos','RelPosition', [15 105 90 20]);
                obj.addUiControl('Parent',hPanel,'String','Zero','style','pushbutton','Tag','pbZeroY','RelPosition', [106 105 40 20],'Enable','on','Callback',@(varargin)obj.zeroSample(2),'TooltipString','Establish relative zero point for Y-axis');
                
                obj.addUiControl('Parent',hPanel,'String','Z','style','text','Tag','lbZPos','HorizontalAlignment','right','RelPosition', [1 127 10 15],'FontWeight','bold');
                obj.addUiControl('Parent',hPanel,'String','etZPos','style','edit','Callback',@obj.changePosition,'Tag','etZPos','RelPosition', [15 127 90 20]);
                obj.addUiControl('Parent',hPanel,'String','Zero','style','pushbutton','Tag','pbZeroZ','RelPosition', [106 127 40 20],'Enable','on','Callback',@(varargin)obj.zeroSample(3),'TooltipString','Establish relative zero point for Z-axis');
                
                obj.addUiControl('Parent',hPanel,'Tag','Ydec','String',char(9650),'Style','pushbutton','Callback',@(varargin)obj.incrementAxis(2,-1),'RelPosition', [35 192 30 30],'TooltipString',['Decrement Y axis' char(10) 'Shortcut: arrow up key'    char(10) 'Holding down the Ctrl key performs a 10x smaller step']);
                obj.addUiControl('Parent',hPanel,'Tag','Yinc','String',char(9660),'Style','pushbutton','Callback',@(varargin)obj.incrementAxis(2,+1),'RelPosition', [35 252 30 30],'TooltipString',['Increment Y axis' char(10) 'Shortcut: arrow down key'  char(10) 'Holding down the Ctrl key performs a 10x smaller step']);
                obj.addUiControl('Parent',hPanel,'Tag','Xdec','String',char(9664),'Style','pushbutton','Callback',@(varargin)obj.incrementAxis(1,-1),'RelPosition', [5  222 30 30],'TooltipString',['Decrement X axis' char(10) 'Shortcut: arrow left key'  char(10) 'Holding down the Ctrl key performs a 10x smaller step']);
                obj.addUiControl('Parent',hPanel,'Tag','Xinc','String',char(9654),'Style','pushbutton','Callback',@(varargin)obj.incrementAxis(1,+1),'RelPosition', [65 222 30 30],'TooltipString',['Increment X axis' char(10) 'Shortcut: arrow right key' char(10) 'Holding down the Ctrl key performs a 10x smaller step']);
                obj.addUiControl('Parent',hPanel,'Tag','XYstep','Style','edit','Bindings',{obj 'xyIncrement' 'value' '%.1f'},'RelPosition', [35 222 30 30],'TooltipString','Step size for XY-axis');
                
                obj.addUiControl('Parent',hPanel,'Tag','Zdec','String',char(9650),'Style','pushbutton','Callback',@(varargin)obj.incrementAxis(3,-1),'RelPosition', [102 192 30 30],'TooltipString',['Decrement Z axis' char(10) 'Shortcut: PgUp key' char(10) 'Holding down the Ctrl key performs a 10x smaller step']);
                obj.addUiControl('Parent',hPanel,'Tag','Zstep','Style','edit','Bindings',{obj 'zIncrement' 'value' '%.1f'},'RelPosition', [102 222 30 30],'TooltipString','Step size for Z-axis');
                obj.addUiControl('Parent',hPanel,'Tag','Zinc','String',char(9660),'Style','pushbutton','Callback',@(varargin)obj.incrementAxis(3,+1),'RelPosition', [102 252 30 30],'TooltipString',['Increment Z axis' char(10) 'Shortcut: PgDn key' char(10) 'Holding down the Ctrl key performs a 10x smaller step']);
                
                obj.addUiControl('Parent',hPanel,'String','Reinit Motors','style','pushbutton','Tag','pbReinit','RelPosition', [5 282 70 20],'Enable','on','Callback',@(varargin)obj.reinitMotors(),'TooltipString','Reinit communication with motor controller');
                obj.addUiControl('Parent',hPanel,'String','Align','style','pushbutton','Tag','pbAlignMotors','RelPosition', [75 282 40 20],'Enable','on','Callback',@(varargin)obj.alignMotors(),'TooltipString','Align motor coordinate system to scan coordinate system');
                obj.addUiControl('Parent',hPanel,'String','Tilt','style','pushbutton','Tag','pbTiltMotors','RelPosition', [115 282 30 20],'Enable','on','Callback',@(varargin)obj.tiltMotors(),'TooltipString','Specify objective rotation (azimuth/elevation)');
                
                obj.addUiControl('Parent',hPanel,'String','','style','edit','Tag','etPlaceholder','RelPosition', [15 105 90 20], 'Visible','off');
            end
            
            function makeFastZPanel(hParent)
                hPanel = most.gui.uipanel('Title','FastZ','Parent',hParent);
                
                obj.addUiControl('Parent',hPanel,'String','Goto Zero','style','pushbutton','Tag','pbFastZGotoZero','RelPosition', [5 42 55 20],'Enable','on','Callback',@(varargin)obj.fastZGoto(0),'TooltipString','Move FastZ actuator to zero position');
                
                obj.addUiControl('Parent',hPanel,'String','Target','style','text','Tag','lbFastZTarget','RelPosition', [3 63 55 15]);
                obj.addUiControl('Parent',hPanel,'Tag','FastZTarget','Style','edit','Bindings',{obj.hModel.hFastZ 'positionTarget' 'value' '%.2f'},'RelPosition', [5 82 55 20],'TooltipString','Target position of the FastZ actuator.');
                obj.addUiControl('Parent',hPanel,'String','Feedback','style','text','Tag','lbFastZFeedback','RelPosition', [6 103 55 15]);
                obj.addUiControl('Parent',hPanel,'Tag','FastZFeedback','Style','edit','Bindings',{obj.hModel.hFastZ 'positionAbsolute' 'value' '%.2f'},'RelPosition', [5 122 55 20],'Enable','off','BackgroundColor',most.constants.Colors.lightGray,'TooltipString','Feedback of the FastZ actuator.','ButtonDownFcn',@(varargin)obj.queryFastZPosition);
                
                obj.addUiControl('Parent',hPanel,'Tag','FastZdec','String',char(9650),'Style','pushbutton','Callback',@(varargin)obj.incrementFastZ(-1),'RelPosition', [17 192 30 30],'TooltipString',['Decrement FastZ actuator position' char(10) 'Alternative: hover mouse over axes and use scroll wheel' char(10) 'Holding down the Ctrl key performs a 10x smaller step']);
                obj.addUiControl('Parent',hPanel,'Tag','FastZstep','Style','edit','Bindings',{obj 'fastZIncrement' 'value' '%.1f'},'RelPosition', [17 222 30 30],'TooltipString','Step size for FastZ actuator');
                obj.addUiControl('Parent',hPanel,'Tag','FastZinc','String',char(9660),'Style','pushbutton','Callback',@(varargin)obj.incrementFastZ(+1),'RelPosition', [17 252 30 30],'TooltipString',['Increment FastZ actuator position' char(10) 'Alternative: hover mouse over axes and use scroll wheel' char(10) 'Holding down the Ctrl key performs a 10x smaller step']);
                
                obj.addUiControl('Parent',hPanel,'String','Align','style','pushbutton','Tag','pbAlignFastZ','RelPosition', [5 282 55 20],'Enable','on','Callback',@(varargin)obj.alignFastZ,'TooltipString','Align FastZ actuator to motor coordinate system');
                obj.addUiControl('Parent',hPanel,'String','Calibrate','style','pushbutton','Tag','pbCalibrateFastZ','RelPosition', [5 149 55 20],'Enable','on','Callback',@(varargin)obj.calibrateFastZ,'TooltipString','Calibrate FastZ actuator feedback. This will move the FastZ actuator through its entire range.');
            end
        end
    end
    
    methods
        function simulatedAxesChanged(obj,varargin)
            hCtls = [obj.etXPos.hCtl obj.etYPos.hCtl obj.etZPos.hCtl];
            sim = obj.hModel.hMotors.simulatedAxes;
            
            set(hCtls(sim),'BackgroundColor',[0.75 0.75 0.75]);
            set(hCtls(sim),'TooltipString','Simulated Axis');
        end
        
        function errorStatusChanged(obj,varargin)
            msgs = obj.hModel.hMotors.errorMsg;
            hCtls_all = [obj.etXPos.hCtl obj.etYPos.hCtl obj.etZPos.hCtl];
            anyErr = 0;
            for motorIdx = 1:numel(msgs)
                hMotor = obj.hModel.hMotors.hMotors{motorIdx};
                msg = msgs{motorIdx};
                dimMap = obj.hModel.hMotors.motorDimMap{motorIdx};
                dimMap(isnan(dimMap)) = [];
                hCtls = hCtls_all(dimMap);
                if ~isempty(msg)
                    tip = sprintf('Motor error for %s:\n%s',class(hMotor),msg);
                    set(hCtls,'BackgroundColor',[1 0.75 0.75]);
                    set(hCtls,'TooltipString',tip);
                    anyErr = 1;
                else
                    if ~hMotor.isHomed
                        c = 'y';
                    else
                        c = [1 1 1];
                    end
                    set(hCtls,'BackgroundColor',c);
                    set(hCtls,'TooltipString','');
                end
            end
            
            if anyErr
                obj.pbReinit.hCtl.BackgroundColor = 'y';
            else
                obj.pbReinit.hCtl.BackgroundColor = .94*ones(1,3);
            end
        end
        
        function fastZGoto(obj,z)
            obj.hModel.hFastZ.positionTarget = z;
        end
        
        function alignFastZ(obj)
            scanimage.util.premiumFeature();
        end
        
        function calibrateFastZ(obj)
            obj.hModel.hWaveformManager.calibrateScanner('Z')
        end
        
        function reinitMotors(obj)
            try
                obj.hModel.hMotors.reinit();
                obj.errorStatusChanged();
                obj.simulatedAxesChanged();
                if obj.hModel.hMotors.errorTf
                    warndlg('One or more motors failed to initialize.', 'ScanImage');
                end
            catch ME
                msg = ['Motor reinitialization failed. Error: ' ME.message];
                most.ErrorHandler.logAndReportError(ME,msg);
                warndlg(msg,'Motor Control');
            end
        end
        
        function alignMotors(obj)
            obj.hController.showGUI('motorsAlignmentControls');
            obj.hController.raiseGUI('motorsAlignmentControls');
        end
        
        function tiltMotors(obj)
            az = obj.hModel.hMotors.azimuth;
            el = obj.hModel.hMotors.elevation;
            
            prompt = {'Azimuth [degree]','Elevation [degree]'};
            dlgtitle = 'Configure Motor Tilt';
            dims = [1 35];
            definput = {sprintf('%.2f',az),sprintf('%.2f',el)};
            answer = inputdlg(prompt,dlgtitle,dims,definput);
            
            if isempty(answer)
                return % user cancelled
            end
            
            answer = str2double(answer);
            validateattributes(answer,{'numeric'},{'nonnan','finite'});
            
            obj.hModel.hMotors.azimuth = answer(1);
            obj.hModel.hMotors.elevation = answer(2);
        end
        
        function zeroSample(obj,axes)
            obj.hModel.hMotors.setRelativeZero(axes);
        end
        
        function clearZero(obj)
            obj.hModel.hMotors.clearRelativeZero();
        end
        
        function queryPosition(obj,varargin)
            obj.hModel.hMotors.queryPosition();
        end
        
        function dragAxes(obj,varargin)
            % no op
        end
        
        function dragFocus(obj,varargin)
            obj.hFig.WindowButtonMotionFcn = @move;
            obj.hFig.WindowButtonUpFcn     = @stop;
            
            function move(varargin)
                try
                    if yyaxisAvailable()
                        yyaxis(obj.hAx,'left');
                    end                    
                    
                    pt = obj.hAx.CurrentPoint(1,1:2);
                    obj.hModel.hFastZ.positionTarget = round(pt(2));
                catch ME
                end
            end
            
            function stop(varargin)
                obj.hFig.WindowButtonMotionFcn = [];
                obj.hFig.WindowButtonUpFcn = [];
            end
        end
        
        function scroll(obj,src,evt)
            if most.gui.isMouseInAxes(obj.hAx)
                try
                    roundDigits = 0;
                    obj.incrementFastZ(-evt.VerticalScrollCount,roundDigits);
                catch ME
                end
            end
        end
        
        function keyPressed(obj,src,evt)
            switch evt.Key
                case 'rightarrow'
                    obj.incrementAxis(1,+1);
                case 'leftarrow'
                    obj.incrementAxis(1,-1);
                case 'uparrow'
                    obj.incrementAxis(2,-1);
                case 'downarrow'
                    obj.incrementAxis(2,+1);
                case 'pagedown'
                    obj.incrementAxis(3,+1);
                case 'pageup'
                    obj.incrementAxis(3,-1);
            end
        end
        
        function incrementAxis(obj,axis,direction,roundDigits)            
            if nargin < 4
                roundDigits = [];
            end
            
            if obj.hModel.hMotors.moveInProgress
                return
            end
            
            hPos = obj.hModel.hMotors.getPosition(obj.hCSDisplay);
            pos = hPos.points;
            
            speedFactor = obj.getSpeedFactor();
            
            if axis <= 2
                increment = speedFactor * direction * obj.xyIncrement;
                pos(axis) = roundTo(pos(axis) + increment,roundDigits);
            elseif axis == 3
                increment = speedFactor * direction * obj.zIncrement;
                pos(axis) = roundTo(pos(axis) + increment,roundDigits);
            else
                assert(false);
            end
            
            hCtls = [obj.Xdec.hCtl obj.Xinc.hCtl obj.Ydec.hCtl obj.Yinc.hCtl obj.Zdec.hCtl obj.Zinc.hCtl];
            hCtl = hCtls(2*axis - double(sign(direction)<0));
            
            oldColor = hCtl.BackgroundColor;            
            hCtl.BackgroundColor = [0.65 1 0.65];
            
            try
                hPos = scanimage.mroi.coordinates.Points(obj.hCSDisplay,pos);
                obj.hModel.hMotors.move(hPos);
            catch ME
                hCtl.BackgroundColor = oldColor;
                rethrow(ME);
            end
            hCtl.BackgroundColor = oldColor;
        end
        
        function incrementFastZ(obj,direction,roundDigits)
            if nargin < 3
                roundDigits = [];
            end
            
            speedFactor = obj.getSpeedFactor();
            
            increment = speedFactor * direction * obj.fastZIncrement;
            
            hCtls = [obj.FastZdec.hCtl obj.FastZinc.hCtl];
            hCtl = hCtls(1.5 + 0.5*sign(direction));
            
            oldColor = hCtl.BackgroundColor;            
            hCtl.BackgroundColor = [0.65 1 0.65];
            
            try
                obj.hModel.hFastZ.positionTarget = roundTo(obj.hModel.hFastZ.positionTarget + increment,roundDigits);
            catch ME
                hCtl.BackgroundColor = oldColor;
                rethrow(ME);
            end
            hCtl.BackgroundColor = oldColor;
        end
        
        function speedFactor = getSpeedFactor(obj)
            if ismember('control',obj.hFig.CurrentModifier)
                speedFactor = 0.1;
            else
                speedFactor = 1;
            end
        end
        
        function changePosition(obj,src,evt)            
            switch src.Tag
                case 'etXPos'
                    dim = 1;
                case 'etYPos'
                    dim = 2;
                case 'etZPos'
                    dim = 3;
                otherwise
                    error('Unknown dimension');
            end
            
            v = str2double(src.String);
            
            obj.hFig.CurrentObject = [];
            uicontrol(obj.etPlaceholder.hCtl); % set focus to placeholder so that live update is not blocked
            
            try
                validateattributes(v,{'numeric'},{'scalar','nonnan','finite','real'});
                
                obj.hModel.hMotors.queryPosition();
                hPt = obj.hModel.hMotors.getPosition(obj.hCSDisplay);
                pt = hPt.points;
                pt(dim) = v;                
                hPt = scanimage.mroi.coordinates.Points(obj.hCSDisplay,pt);
                obj.hModel.hMotors.move(hPt);
            catch ME
                obj.update();
                rethrow(ME);
            end
        end
        
        function update(obj,varargin)
            hPt = scanimage.mroi.coordinates.Points(obj.hModel.hCoordinateSystems.hCSReference,[0,0,0]);
            hPt = hPt.transform(obj.hCSDisplay);
            pt  = hPt.points;
            
            currentObj = obj.hFig.CurrentObject;
            
            if ~isequal(currentObj,obj.etXPos)
                obj.etXPos.String = sprintf('%.2f',pt(1));
            end
            
            if ~isequal(currentObj,obj.etYPos)
                obj.etYPos.String = sprintf('%.2f',pt(2));
            end
            
            if ~isequal(currentObj,obj.etZPos)
                obj.etZPos.String = sprintf('%.2f',pt(3));
            end
            
            obj.redraw();
        end
        
        function redraw(obj,varargin)          
            hPtFocus = scanimage.mroi.coordinates.Points(obj.hModel.hCoordinateSystems.hCSFocus,[0,0,0]);
            hPtFocusRef = hPtFocus.transform(obj.hModel.hCoordinateSystems.hCSReference);
            
            focusRefZ = hPtFocusRef.points(1,3);
            obj.hLineFocusMarker.XData = 0.5;
            obj.hLineFocusMarker.YData = focusRefZ;
            
            obj.hLineFocus.XData = [0 1];
            obj.hLineFocus.YData = [focusRefZ focusRefZ];
            
            hPtFocusSampleRelative = hPtFocus.transform(obj.hModel.hCoordinateSystems.hCSSampleRelative);
            focusSampleZ = hPtFocusSampleRelative.points(1,3);
            obj.hTextFocus.Position = [0.5 focusRefZ];
            obj.hTextFocus.String = sprintf('\\fontsize{8.5}%.2f\\fontsize{2}\n',focusSampleZ);
            
            %%% update left axis            
            if isempty(obj.hModel.hFastZ.hScanner)
                travelRange = [];
                YLim = [-100 100];
            else
                travelRange = sort(obj.hModel.hFastZ.hScanner.travelRange);
                extendRange = 1.2;
                midPoint = sum(travelRange)/2;
                range = diff(travelRange) * extendRange;
                
                YLim = midPoint + range/2 * [-1 1];
            end
            
            if isprop(obj.hAx,'YAxis')
                obj.hAx.YAxis(1).Limits = YLim;
            else
                % Matlab 2015a workaround
                obj.hAx.YLim = YLim;
            end
            
            if isempty(travelRange)
                V = [];
                F = [];
            else
                V = [0 YLim(1);
                     0 travelRange(1);
                     1 travelRange(1);
                     1 YLim(1);
                     ...
                     0 YLim(2);
                     0 travelRange(2);
                     1 travelRange(2);
                     1 YLim(2)];
                 
                F = [1 2 3 4;
                     5 6 7 8];
            end
            
            obj.hPatchFastZLimits.Vertices = V;
            obj.hPatchFastZLimits.Faces = F;
            
            pts = [0 0 YLim(1);
                   0 0 YLim(2)];
            hPts = scanimage.mroi.coordinates.Points(obj.hModel.hCoordinateSystems.hCSReference,pts);
            hPts = hPts.transform(obj.hModel.hCoordinateSystems.hCSSampleRelative);
            YLim_sample = hPts.points(:,3);
            
            %%% update right axis
            if isprop(obj.hAx,'YAxis') && numel(obj.hAx.YAxis)>1
                yyaxis(obj.hAx,'right');
                obj.hAx.YAxis(2).Limits = sort(YLim_sample);
            end
        end
        
        function queryFastZPosition(obj)
            obj.hModel.hFastZ.positionAbsolute = NaN;
        end
    end
    
    methods
        function changeCoordinateSystem(obj,varargin)
            csOptions = obj.hPmCoordinateSystem.String;
            cs = csOptions{obj.hPmCoordinateSystem.Value};
            
            switch lower(cs)
                case 'stage'
                    hCS = obj.hModel.hCoordinateSystems.hCSStageRelative;
                case 'sample'
                    hCS = obj.hModel.hCoordinateSystems.hCSSampleRelative;
                case 'raw motor'
                    hCS = obj.hModel.hMotors.hCSAxesPosition;
                otherwise
                    error('Unkown coordinate system: %s',cs);
            end
            obj.hCSDisplay = hCS;
        end
    end
    
    %% Getter/Setter
    methods
        function set.hCSDisplay(obj,val)
            obj.hCSDisplay = val;
            obj.update();
        end
    end
end

function tf = yyaxisAvailable()
    tf = ~verLessThan('matlab', '9.0');
end

function val = roundTo(val,digits)
    if ~isempty(digits)
        val = round(val,digits);
    end
end


%--------------------------------------------------------------------------%
% MotorControls.m                                                          %
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
