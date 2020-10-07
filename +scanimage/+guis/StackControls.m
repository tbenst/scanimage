classdef  StackControls < most.Gui    
    %% GUI PROPERTIES
    properties (SetAccess = protected,SetObservable,Hidden)
        hListeners = event.listener.empty(1,0);
    end
    
    properties (SetObservable)
        hAx
        hLineBounds;
        hLine;
        hLineFocus;
        hLineFocusMarker;
        hPatchFastZLimits;
    end
    
    properties (Hidden)
        tabStackDefinition
        tabUniform
        tabBounded
        tabArbitrary
        
        tabStackMode
        tabSlow
        tabFast
        
        hPmWaveformType
        hCbStartEndPower
    end
    
    properties (Hidden, AbortSet)
        YLim
    end
    
    %% LIFECYCLE
    methods
        function obj = StackControls(hModel, hController)
            if nargin < 1
                hModel = [];
            end
            
            if nargin < 2
                hController = [];
            end
            
            obj = obj@most.Gui(hModel, hController, [340 412], 'pixels');
            set(obj.hFig,'Name','STACK CONTROLS');
            set(obj.hFig,'Resize','off');
            
            hFlowMain = most.gui.uiflowcontainer('Parent', obj.hFig,'FlowDirection','LeftToRight');
            
            hFlowAx = most.gui.uiflowcontainer('Parent', hFlowMain,'FlowDirection','TopDown');
            hFlowTabs = most.gui.uiflowcontainer('Parent', hFlowMain,'FlowDirection','TopDown');
                set(hFlowTabs,'WidthLimits',[200,200]);
                
                hFlowDefTab = most.gui.uiflowcontainer('Parent', hFlowTabs,'FlowDirection','LeftToRight');
                    set(hFlowDefTab,'HeightLimits',[210,210]);
                    obj.tabStackDefinition = uitabgroup('Parent', hFlowDefTab,'TabLocation', 'top', 'SelectionChangedFcn', @obj.changeStackDefinition);
                        obj.tabUniform   = uitab('Parent', obj.tabStackDefinition, 'Title', 'Uniform',  'UserData', scanimage.types.StackDefinition.uniform);
                        obj.tabBounded   = uitab('Parent', obj.tabStackDefinition, 'Title', 'Bounded',  'UserData', scanimage.types.StackDefinition.bounded);
                        obj.tabArbitrary = uitab('Parent', obj.tabStackDefinition, 'Title', 'Arbitrary','UserData', scanimage.types.StackDefinition.arbitrary);
                
                hFlowModeTab = most.gui.uiflowcontainer('Parent', hFlowTabs,'FlowDirection','LeftToRight');
                    %set(hFlowModeTab,'HeightLimits',[180,180]);
                    obj.tabStackMode = uitabgroup('Parent', hFlowModeTab,'TabLocation', 'top', 'SelectionChangedFcn', @obj.changeStackMode);
                        obj.tabSlow   = uitab('Parent', obj.tabStackMode, 'Title', '     Slow     ', 'UserData', scanimage.types.StackMode.slow);
                        obj.tabFast   = uitab('Parent', obj.tabStackMode, 'Title', '     Fast     ', 'UserData', scanimage.types.StackMode.fast);
            
            obj.makeAxes(hFlowAx);
            obj.populateTabs(hFlowTabs);
            
            obj.hListeners(end+1) = most.ErrorHandler.addCatchingListener(obj.hModel.hStackManager,'stackDefinition','PostSet',@obj.tabsChanged);
            obj.hListeners(end+1) = most.ErrorHandler.addCatchingListener(obj.hModel.hStackManager,'stackMode',      'PostSet',@obj.tabsChanged);
            obj.hListeners(end+1) = most.ErrorHandler.addCatchingListener(obj.hModel.hStackManager,'zs',             'PostSet',@obj.zsChanged);
            obj.hListeners(end+1) = most.ErrorHandler.addCatchingListener(obj.hModel.hStackManager,'hStackZStartPos','PostSet',@obj.stackBoundsChanged);
            obj.hListeners(end+1) = most.ErrorHandler.addCatchingListener(obj.hModel.hStackManager,'hStackZEndPos',  'PostSet',@obj.stackBoundsChanged);
            obj.hListeners(end+1) = most.ErrorHandler.addCatchingListener(obj.hModel.hCoordinateSystems.hCSFocus,    'changed',@obj.zsChanged);
            obj.hListeners(end+1) = most.ErrorHandler.addCatchingListener(obj.hModel.hBeams,       'pzAdjust',       'PostSet',@obj.validateSettings);
            obj.hListeners(end+1) = most.ErrorHandler.addCatchingListener(obj.hModel,              'imagingSystem',  'PostSet',@obj.validateSettings);
        end
        
        function makeAxes(obj,hParent)
            obj.hAx = axes('Parent',hParent,'XLim',[0,1],'XTick',[],'YAxisLocation','right');
            obj.hAx.XTick = 1;
            obj.hAx.XTickLabel = {'Sample [um]'};
            obj.hAx.OuterPosition = [0.5 0 0.9 1];
            title(obj.hAx,'Z-Stack','FontWeight','normal');
            box(obj.hAx,'on');
            grid(obj.hAx,'on');
            obj.hPatchFastZLimits = patch('Parent',obj.hAx,'Faces',[],'Vertices',[],'FaceColor',[0 0 0],'FaceAlpha',0.2,'LineStyle','none');
            obj.hLineBounds = line('Parent',obj.hAx,'Color',[0.5 0.5 0.5],'LineWidth',1.5,'XData',[],'YData',[]);
            obj.hLine = line('Parent',obj.hAx,'Color',[0 0 1],'LineWidth',1.5,'XData',[],'YData',[]);
            obj.hLineFocus = line('Parent',obj.hAx,'Color',[1 0 0],'LineWidth',0.5,'XData',[],'YData',[]);
            obj.hLineFocusMarker = line('Parent',obj.hAx,'Color',[1 0 0],'LineWidth',1,'XData',[],'YData',[],'LineStyle','none','Marker','*');
            view(obj.hAx,0,-90);
        end
        
        function stackBoundsChanged(obj,varargin)
            if isempty(obj.hModel.hStackManager.hStackZStartPos)
                obj.pbSetStackStart.String = 'Set Start';
            else
                obj.pbSetStackStart.String = 'Clear Start';
            end
            
            if isempty(obj.hModel.hStackManager.hStackZEndPos)
                obj.pbSetStackEnd.String = 'Set End';
            else
                obj.pbSetStackEnd.String = 'Clear End';
            end
            
            obj.zsChanged();
        end
        
        function zsChanged(obj,varargin)
            obj.updateAxes();
            obj.validateSettings();
        end
        
        function updateAxes(obj)
            fZ = updateFocus();
            zs = updateZseries();
            bs = updateBounds();
            
            allZs = vertcat(fZ(:),zs(:),bs(:));
            
            updateAxesLimits(allZs);
            updateFastZLimits();
            
            %%% nested functions
            function zs = updateFocus()
                hCSDisplay = obj.hModel.hStackManager.hCSDisplay;
                hFocalPt = scanimage.mroi.coordinates.Points(obj.hModel.hCoordinateSystems.hCSFocus,[0,0,0]);
                hFocalPt = hFocalPt.transform(hCSDisplay);
                zFocus = hFocalPt.points(3);
                
                obj.hLineFocus.XData = [0 1];
                obj.hLineFocus.YData = [zFocus zFocus];
                
                obj.hLineFocusMarker.XData = 0.5;
                obj.hLineFocusMarker.YData = zFocus;
                
                zs = zFocus;
            end
            
            function zs = updateZseries()
                if obj.hModel.hStackManager.enable
                    zs = unique(obj.hModel.hStackManager.zs);
                    zsXData = repmat([0;1],1,numel(zs));
                    zsYData = [zs(:)';zs(:)'];
                    
                    zsXData(end+1,:) = NaN;
                    zsYData(end+1,:) = NaN;
                else
                    zs = [];
                    zsXData = [];
                    zsYData = [];
                end
                
                obj.hLine.XData = zsXData(:);
                obj.hLine.YData = zsYData(:);
            end
            
            function zs = updateBounds()
                zs = [];
                xdata = [];
                ydata = [];
                
                if obj.hModel.hStackManager.stackDefinition == scanimage.types.StackDefinition.bounded
                    zStart = obj.hModel.hStackManager.stackZStartPos;
                    zEnd = obj.hModel.hStackManager.stackZEndPos;
                    
                    zs = [zStart;zEnd];
                    
                    ydata = [zStart,zEnd;zStart,zEnd];
                    xdata = repmat([0;1],1,size(ydata,2));
                    
                    if ~isempty(ydata)
                        ydata(end+1,:) = NaN;
                        xdata(end+1,:) = NaN;
                    end
                end
                
                obj.hLineBounds.XData = xdata(:);
                obj.hLineBounds.YData = ydata(:);
            end
            
            function updateFastZLimits()
                slowZwithFastZActuator = obj.hModel.hStackManager.isSlowZ && obj.hModel.hStackManager.stackActuator == scanimage.types.StackActuator.fastZ;
                fastZ = obj.hModel.hStackManager.isFastZ;
                
                if fastZ || slowZwithFastZActuator                   
                    hCSDisplay = obj.hModel.hStackManager.hCSDisplay;
                    hCSReference = obj.hModel.hCoordinateSystems.hCSReference;
                    
                    try
                        travelRange = obj.hModel.hFastZ.hScanner.hDevice.travelRange;
                    catch ME
                        travelRange = [];
                    end
                    
                    if ~isempty(travelRange)
                        Range = scanimage.mroi.coordinates.Points(hCSReference,[0 0 travelRange(1);0 0 travelRange(2)]);
                        Range = Range.transform(hCSDisplay);
                        travelRange = Range.points(:,3);
                        travelRange = sort(travelRange);
                    end
                    
                    V = zeros(0,2);
                    F = zeros(0,4);
                    
                    if ~isempty(travelRange) && travelRange(1) > obj.YLim(1)
                        V = [0 obj.YLim(1);
                             0 min(travelRange(1),obj.YLim(2));
                             1 min(travelRange(1),obj.YLim(2));
                             1 obj.YLim(1)];
                        F = [1 2 3 4];
                    end
                    
                    if ~isempty(travelRange) && travelRange(2) < obj.YLim(2)
                        V_ = [0 obj.YLim(2);
                             0 max(travelRange(2),obj.YLim(1));
                             1 max(travelRange(2),obj.YLim(1));
                             1 obj.YLim(2);];
                        F_ = [1 2 3 4];
                        
                        V = vertcat(V,V_);
                        F = vertcat(F,F_+numel(F));
                    end
                    
                    obj.hPatchFastZLimits.Vertices = V;
                    obj.hPatchFastZLimits.Faces = F;
                else
                    obj.hPatchFastZLimits.Vertices = [];
                    obj.hPatchFastZLimits.Faces = [];
                end
            end
            
            function updateAxesLimits(allZs)
                allZs(isnan(allZs)) = [];
                
                extent = max(allZs)-min(allZs);
                centerZ = (min(allZs)+max(allZs))/2;
                
                if any(isnan([extent centerZ]))
                    return
                end
                
                if isempty(extent) || extent == 0
                    extent = 1;
                end
                
                if isempty(centerZ)
                    centerZ = 0;
                end
                
                YLim_ = centerZ + extent * [-0.5 +0.5] * 1.2;
                YLim_ = [floor(YLim_(1)) ceil(YLim_(2))];
                obj.YLim = YLim_;
            end
        end
        
        function set.YLim(obj,val)
            obj.YLim = val;
            most.gui.Transition(0.5,obj.hAx,'YLim',val);
        end
        
        function populateTabs(obj,hParent)
            populateUniformPanel();
            populateBoundedPanel();
            populateArbitraryPanel();
            populateFastPanel();
            populateSlowPanel();
            
            %%% nested functions
            function populateUniformPanel()
                hTab = obj.tabUniform;
                
                most.gui.uicontrol('Parent',hTab,'String','Frames per Slice','style','text','Tag','lbUniformFramesPerSlice','HorizontalAlignment','right','RelPosition', [5 23 100 14]);
                most.gui.uicontrol('Parent',hTab,'String','etFramesPerSlice','style','edit','Bindings',{obj.hModel.hStackManager 'framesPerSlice' 'value'},'Tag','etUniformFramesPerSlice','RelPosition', [110 26 40 20]);
                
                most.gui.uicontrol('Parent',hTab,'String','Number of Slices','style','text','Tag','lbUniformNumSlices','HorizontalAlignment','right','RelPosition', [5 45 100 14]);
                most.gui.uicontrol('Parent',hTab,'String','etNumSlices','style','edit','Bindings',{obj.hModel.hStackManager 'numSlices' 'value'},'Tag','etUniformNumSlices','RelPosition', [110 47 40 20]);
                
                most.gui.uicontrol('Parent',hTab,'String','Number of Volumes','style','text','Tag','lbUniformNumVolumes','HorizontalAlignment','right','RelPosition', [5 67 100 14]);
                most.gui.uicontrol('Parent',hTab,'String','etNumVolumes','style','edit','Bindings',{obj.hModel.hStackManager 'numVolumes' 'value'},'Tag','etUniformNumVolumes','RelPosition', [110 69 40 20]);
                
                most.gui.uicontrol('Parent',hTab,'String','Step Size [um]','style','text','Tag','lbUniformStepSize','HorizontalAlignment','right','RelPosition', [5 88 100 14]);
                most.gui.uicontrol('Parent',hTab,'String','etStepSize','style','edit','Bindings',{obj.hModel.hStackManager 'stackZStepSize' 'value'},'Tag','etUniformStepSize','RelPosition', [110 92 40 20]);
                
                most.gui.uicontrol('Parent',hTab,'String','Centered Stack','style','text','Tag','lbUniformCentered','HorizontalAlignment','right','RelPosition', [5 111 100 14]);
                most.gui.uicontrol('Parent',hTab,'String','','style','checkbox','Bindings',{obj.hModel.hStackManager 'centeredStack' 'value'},'Tag','cbUniformCentered','RelPosition', [123 114 18 20]);
            end
            
            function populateBoundedPanel()
                hTab = obj.tabBounded;
                
                most.gui.uicontrol('Parent',hTab,'String','Frames per Slice','style','text','Tag','lbBoundedFramesPerSlice','HorizontalAlignment','right','RelPosition', [5 23 100 14]);
                most.gui.uicontrol('Parent',hTab,'String','etFramesPerSlice','style','edit','Bindings',{obj.hModel.hStackManager 'framesPerSlice' 'value'},'Tag','etBoundedFramesPerSlice','RelPosition', [110 26 40 20]);
                
                most.gui.uicontrol('Parent',hTab,'String','Number of Slices','style','text','Tag','lbBoundedNumSlices','HorizontalAlignment','right','RelPosition', [5 45 100 14]);
                most.gui.uicontrol('Parent',hTab,'String','etNumSlices','style','edit','Bindings',{obj.hModel.hStackManager 'numSlices' 'value'},'Tag','etBoundedNumSlices','RelPosition', [110 47 40 20]);
                
                most.gui.uicontrol('Parent',hTab,'String','Number of Volumes','style','text','Tag','lbBoundedNumVolumes','HorizontalAlignment','right','RelPosition', [5 67 100 14]);
                most.gui.uicontrol('Parent',hTab,'String','etNumVolumes','style','edit','Bindings',{obj.hModel.hStackManager 'numVolumes' 'value'},'Tag','etBoundedNumVolumes','RelPosition', [110 69 40 20]);
                
                most.gui.uicontrol('Parent',hTab,'String','Step Size [um]','style','text','Tag','lbBoundedStepSize','HorizontalAlignment','right','RelPosition', [5 88 100 14]);
                most.gui.uicontrol('Parent',hTab,'String','etStepSize','style','edit','Bindings',{obj.hModel.hStackManager 'actualStackZStepSize' 'value'},'Tag','etBoundedStepSize','RelPosition', [110 92 40 20],'Enable','off');
                
                obj.addUiControl('Parent',hTab,'String','Set Start','style','pushbutton','Tag','pbSetStackStart','RelPosition', [5 132 60 20],'Callback',@obj.setClearBoundedStackStart);
                most.gui.uicontrol('Parent',hTab,'String','etStackStart','style','edit','Bindings',{obj.hModel.hStackManager 'stackZStartPos' 'value'},'Tag','etStackStart','RelPosition', [67 132 40 20],'Enable','off');
                most.gui.uicontrol('Parent',hTab,'String','etStackStartPower','style','edit','Bindings',{obj.hModel.hStackManager 'stackStartPower' 'value'},'Tag','etStackStartPower','RelPosition', [110 132 70 20],'Enable','off');
                
                obj.addUiControl('Parent',hTab,'String','Set End','style','pushbutton','Tag','pbSetStackEnd','RelPosition', [5 155 60 20],'Callback',@obj.setClearBoundedStackEnd);
                most.gui.uicontrol('Parent',hTab,'String','etStackEnd','style','edit','Bindings',{obj.hModel.hStackManager 'stackZEndPos' 'value'},'Tag','etStackEnd','RelPosition', [67 155 40 20],'Enable','off');
                most.gui.uicontrol('Parent',hTab,'String','etStackEndPower','style','edit','Bindings',{obj.hModel.hStackManager 'stackEndPower' 'value'},'Tag','etStackEndPower','RelPosition', [110 155 70 20],'Enable','off');
                
                obj.hCbStartEndPower = most.gui.uicontrol('Parent',hTab,'String','Use start end powers','style','checkbox','Bindings',{obj.hModel.hStackManager 'useStartEndPowers' 'value'},'Tag','cbUseStartEndPowers','RelPosition', [55 177 126 20]);
                
                most.gui.uicontrol('Parent',hTab,'String','Z','style','text','Tag','lbZ','HorizontalAlignment','right','RelPosition', [68.6666666666664 110.666666666667 21 14]);
                most.gui.uicontrol('Parent',hTab,'String','Powers','style','text','Tag','lbPowers','HorizontalAlignment','right','RelPosition', [128 109.666666666667 40 14]);
            end
            
            function populateArbitraryPanel()
                hTab = obj.tabArbitrary;
                
                most.gui.uicontrol('Parent',hTab,'String','Frames per Slice','style','text','Tag','lbArbitraryFramesPerSlice','HorizontalAlignment','right','RelPosition', [5 23 100 14]);
                most.gui.uicontrol('Parent',hTab,'String','etFramesPerSlice','style','edit','Bindings',{obj.hModel.hStackManager 'framesPerSlice' 'value'},'Tag','etArbitraryFramesPerSlice','RelPosition', [110 26 40 20]);
                
                most.gui.uicontrol('Parent',hTab,'String','Number of Slices','style','text','Tag','lbArbitraryNumSlices','HorizontalAlignment','right','RelPosition', [5 45 100 14]);
                most.gui.uicontrol('Parent',hTab,'String','etNumSlices','style','edit','Bindings',{obj.hModel.hStackManager 'actualNumSlices' 'value'},'Tag','etArbitraryNumSlices','RelPosition', [110 47 40 20],'Enable','off');
                
                most.gui.uicontrol('Parent',hTab,'String','Number of Volumes','style','text','Tag','lbArbitraryNumVolumes','HorizontalAlignment','right','RelPosition', [5 67 100 14]);
                most.gui.uicontrol('Parent',hTab,'String','etNumVolumes','style','edit','Bindings',{obj.hModel.hStackManager 'numVolumes' 'value'},'Tag','etArbitraryNumVolumes','RelPosition', [110 69 40 20]);
                
                most.gui.uicontrol('Parent',hTab,'String','Arbitrary Zs [um]','style','text','Tag','lbArbitraryZs','HorizontalAlignment','left','RelPosition', [7 96 100 14]);
                most.gui.uicontrol('Parent',hTab,'String','etArbZs','style','edit','Bindings',{obj.hModel.hStackManager 'arbitraryZs' 'value'},'Tag','etArbitraryZs','RelPosition', [4 118 181 20]);
                
                most.gui.uicontrol('Parent',hTab,'String','Copy from ROI group','style','pushbutton','Tag','pbCopyFromRoiGroup','RelPosition', [23 141 130 20],'Callback',@obj.copyArbitraryZFromRoiGroup);
            end
            
            function populateFastPanel()
                hTab = obj.tabFast;
                
                most.gui.uicontrol('Parent',hTab,'String','Waveform Type','style','text','Tag','lbFastWaveformType','HorizontalAlignment','right','RelPosition', [20 21 75 14]);
                obj.hPmWaveformType = most.gui.uicontrol('Parent',hTab,'String','autoset','style','popupmenu','Bindings',{obj.hModel.hStackManager 'stackFastWaveformType' 'enum'},'Tag','pmFastWaveformType','RelPosition', [100 24 70 20]);
                
                most.gui.uicontrol('Parent',hTab,'String','Return Home','style','text','Tag','lbFastReturnHome','HorizontalAlignment','right','RelPosition', [88 43 64 15]);
                most.gui.uicontrol('Parent',hTab,'String','','style','checkbox','Bindings',{obj.hModel.hStackManager 'stackReturnHome' 'value'},'Tag','cbFastReturnHome','RelPosition', [155 43 15 15]);
                
                most.gui.uicontrol('Parent',hTab,'String','Flyback Time (ms)','style','text','Tag','lbFastFlybackTime','HorizontalAlignment','right','RelPosition', [27 61 98 14]);
                most.gui.uicontrol('Parent',hTab,'String','etFastFlybackTime','style','edit','Bindings',{obj.hModel.hFastZ 'flybackTime' 'value' '%.3f' 'scaling' 1e3},'Tag','etFastFlybackTime','RelPosition', [129 64 40 20],'TooltipString',['Time allocated for flying back the Z-actuator at the end of the stack.' char(10) 'The flyback time is rounded up to a multiple of the frame duration to determine the number of discarded frames.']);
                
                most.gui.uicontrol('Parent',hTab,'String','# Discard Frames','style','text','Tag','lbFastNumDiscardFlybackFrames','HorizontalAlignment','right','RelPosition', [31 83 94 14]);
                most.gui.uicontrol('Parent',hTab,'String','etFastNumDiscardFlybackFrames','style','edit','Bindings',{obj.hModel.hFastZ 'numDiscardFlybackFramesForDisplay' 'value'},'Tag','etFastNumDiscardFlybackFrames','RelPosition', [129 86 40 20],'Enable','off');
                
                most.gui.uicontrol('Parent',hTab,'String','Actuator Lag (ms)','style','text','Tag','lbFastActuatorLag','HorizontalAlignment','right','RelPosition', [27 105 98 14]);
                most.gui.uicontrol('Parent',hTab,'String','etFastActuatorLag','style','edit','Bindings',{obj.hModel.hFastZ 'actuatorLag' 'value' '%.3f' 'scaling' 1e3},'Tag','etFastActuatorLag','RelPosition', [129 108 40 20]);
                
                most.gui.uicontrol('Parent',hTab,'String','Volume Rate [Hz]','style','text','Tag','lbFastVolumeRate','HorizontalAlignment','right','RelPosition', [35 126 90 13]);
                most.gui.uicontrol('Parent',hTab,'String','etFastVolumeRate','style','edit','Bindings',{obj.hModel.hRoiManager 'scanVolumeRate' 'value' '%.2f'},'Tag','etFastVolumeRate','RelPosition', [129 130 40 20],'Enable','off');
                                
                most.gui.uicontrol('Parent',hTab,'String','Test Waveform','style','pushbutton','RelPosition', [56 154 114 22], 'Enable', 'off');
            end
            
            function populateSlowPanel()
                hTab = obj.tabSlow;
                
                most.gui.uicontrol('Parent',hTab,'String','Actuator','style','text','Tag','lbActuator','HorizontalAlignment','right','RelPosition', [46 21 51 14]);
                most.gui.uicontrol('Parent',hTab,'String','autoset','style','popupmenu','Bindings',{obj.hModel.hStackManager 'stackActuator' 'enum'},'Tag','pmActuator','RelPosition', [100 24 70 20]);
                
                most.gui.uicontrol('Parent',hTab,'String','Return Home','style','text','Tag','lbSlowReturnHome','HorizontalAlignment','right','RelPosition', [88 43 64 15]);
                most.gui.uicontrol('Parent',hTab,'String','','style','checkbox','Bindings',{obj.hModel.hStackManager 'stackReturnHome' 'value'},'Tag','cbSlowReturnHome','RelPosition', [155 43 15 15]);
                
                most.gui.uicontrol('Parent',hTab,'String','Close Shutter btwn Slices','style','text','Tag','lbCloseShutter','HorizontalAlignment','right','RelPosition', [21 60 130 15]);
                most.gui.uicontrol('Parent',hTab,'String','','style','checkbox','Bindings',{obj.hModel.hStackManager 'closeShutterBetweenSlices' 'value'},'Tag','cbCloseShutter','RelPosition', [155 62 18 20]);
            end
        end
        
        function delete(obj)
            most.idioms.safeDeleteObj(obj.hListeners);
            most.idioms.safeDeleteObj(obj.hFig);
        end
    end
    
    %% User Methods
    methods
        function validateSettings(obj,varargin)            
            if obj.hModel.hStackManager.enable && obj.hModel.hStackManager.stackMode == scanimage.types.StackMode.fast
                if obj.hModel.hStackManager.stackDefinition == scanimage.types.StackDefinition.arbitrary && ...
                        obj.hModel.hStackManager.stackFastWaveformType == scanimage.types.StackFastWaveformType.sawtooth
                    obj.hPmWaveformType.hCtl.BackgroundColor = most.constants.Colors.lightRed;
                elseif obj.hModel.hStackManager.framesPerSlice > 1 && ...
                        obj.hModel.hStackManager.stackFastWaveformType == scanimage.types.StackFastWaveformType.sawtooth
                    obj.hPmWaveformType.hCtl.BackgroundColor = most.constants.Colors.lightRed;
                else
                    obj.hPmWaveformType.hCtl.BackgroundColor = most.constants.Colors.white;
                end
            else
                obj.hPmWaveformType.hCtl.BackgroundColor = most.constants.Colors.white;
            end
            
            % validate bounded beam settings
            beamIds = obj.hModel.hScan2D.beamIds;
            pzAdjust = obj.hModel.hBeams.pzAdjust(beamIds);
            
            if ~isempty(beamIds) && ~all(pzAdjust) && obj.hModel.hStackManager.overrideLZs
                obj.hCbStartEndPower.hCtl.BackgroundColor = most.constants.Colors.lightRed;
                obj.hCbStartEndPower.hCtl.TooltipString = 'Power/Depth Adjustment is not activated for active beam.';
            else
                obj.hCbStartEndPower.hCtl.BackgroundColor = most.constants.Colors.lightGray;
                obj.hCbStartEndPower.hCtl.TooltipString = '';
            end
        end
        
        function showWaveforms(obj,varargin)
            obj.hController.hWaveformControls.openGui('Z');
        end
        
        function changeStackDefinition(obj,varargin)
            tab = obj.tabStackDefinition.SelectedTab;
            def = tab.UserData;
            obj.hModel.hStackManager.stackDefinition = def;
        end
        
        function changeStackMode(obj,varargin)
            tab = obj.tabStackMode.SelectedTab;
            def = tab.UserData;
            obj.hModel.hStackManager.stackMode = def;
        end
        
        function tabsChanged(obj,varargin)
            defTabs = obj.tabStackDefinition.Children;
            defs = [defTabs.UserData];
            mask = defs==obj.hModel.hStackManager.stackDefinition;
            obj.tabStackDefinition.SelectedTab = defTabs(mask);
            
            modeTabs = obj.tabStackMode.Children;
            modes = [modeTabs.UserData];
            mask = modes==obj.hModel.hStackManager.stackMode;
            obj.tabStackMode.SelectedTab = modeTabs(mask);
        end
        
        function copyArbitraryZFromRoiGroup(obj,varargin)
            obj.hModel.hStackManager.arbitraryZs = obj.hModel.hRoiManager.currentRoiGroup.zs;
        end
        
        function setClearBoundedStackStart(obj,varargin)
            if isempty(obj.hModel.hStackManager.stackZStartPos)
                obj.hModel.hStackManager.setStackStart();
            else
                obj.hModel.hStackManager.clearStackStart();
            end
        end
        
        function setClearBoundedStackEnd(obj,varargin)
            if isempty(obj.hModel.hStackManager.stackZEndPos)
                obj.hModel.hStackManager.setStackEnd();
            else
                obj.hModel.hStackManager.clearStackEnd();
            end
        end
    end
end


%--------------------------------------------------------------------------%
% StackControls.m                                                          %
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
