classdef ScannerPage < scanimage.guis.configuration.ConfigurationPage
    
    properties
        numChans;
        
        etName;
        hShutterTable;
        hBeamTable;
        pmAcqDaq;
        
        hResSection;
        hResPanel;
        hGalvoSection;
        hGalvoPanel;
        galvoDaqFlow;
        vdaqHideSections;
        vdaqShowSections;
        advancedStuff;
        offsetStuff;
        nonRmrStuff;
        slmStuff;
        nameStuff;
        extendedStuff;
        
        hCutomSignalCondPopup;
        hDigitalIODevicePopUp;
        hResSyncTermPopUp;
        hNominalFrequencyEdit;
        hChannelTable;
        hExternalSampleClockRateEdit;
        hResMaxAngularRangeEdit;
        hResZoomDeviceText;
        hResZoomDevicePopUp;
        hResZoomChannelIDPopUp;
        hResEnableTerminalPopUp;
        hResMaxVoltageCmdEdit;
        hResSettlingTimeEdit;
        
        hGalvoCtlDaqPopUp
        hGalvoFdbkDaqPopUp
        hOffsetDaqPopUp
        
        hXGalvoPanel;
        hXGalvoAnalogOutputChannelIDPopUp;
        hXGalvoMaxAngularRangeEdit;
        hXGalvoOpticalConversionFactorEdit;
        hXGalvoParkAngleEdit;
        hXGalvoInputChannelIDPopUp;
        hXGalvoAnalogOutputOffsetPopUp;
        hXGalvoMaximumVoltageOutputEdit;
        hXGalvoExtendedFov;
        
        hYGalvoPanel;
        hYGalvoAnalogOutputChannelIDPopUp;
        hYGalvoInputChannelIDPopUp;
        hYGalvoMaxAngularRangeEdit;
        hYGalvoParkAngleEdit;
        hYGalvoOpticalConversionFactorEdit;
        hYGalvoAnalogOutputOffsetPopUp;
        hYGalvoMaximumVoltageOutputEdit;
        
        hLutDevicePopUp;
        hLutChannelPopUp;
        
        hAdvButtonPanel;
        hLaserPortPop;
        hExternalSampleClockRateText;
        
        tfMap = containers.Map({true false}, {'on' 'off'});
        
        hasXGalvo = false;
        defaultExtendedFov = true;
    end
    
    properties (SetObservable)
        scannerName;
        scannerType;
        scannerTypeSel = 1;
        
        canLinearScan;
        canPhotostim;
        
        acqDevId = '';
        acqDev = '';
        acqDevIsRdi = false;
        acqDevChoices = {};
        
        digIoDev = '';
        useExtClk = false;
        exprtClk = false;
        zoomCtlDaq = '';
        galvoDaq = '';
        xGalvoChanSel = '';
        
        galvoFeedbackDaq = '';
        galvoOffsetDaq = '';
        
        aisFixed;
        internalSet = false;
        
        focalLength = 100;
        slmMediumRefractiveIdx = 1.000293;
        objectiveMediumRefractiveIdx = 1.333;
        zeroOrderBlockRadius = 0.01;
        
        slmTpye = '';
        slmChoices = {};
        slmLinScanner = '';
        slmLinscanChoices = {};
        lutDev = '';
        
        resAngularRange = 26;
        xgalvoAngularRange = 20;
        extendedFov = 1;
    end
    
    properties (Constant)
        modelClass = '';
    end
    
    methods
        function obj = ScannerPage(hConfigEditor, mdfHeading, create)
            if nargin < 3 || isempty(create)
                create = false;
            end
            obj = obj@scanimage.guis.configuration.ConfigurationPage(hConfigEditor,false,false);
            
            if ~create
                obj.heading = mdfHeading;
                
                c = regexp(mdfHeading,'.*\((.*)\)','tokens');
                obj.scannerName = c{1}{1};
                nameChangeVis = 'on';
                nameChangeEn = 'inactive';
                nameChangeColor = .95*ones(1,3);
            else
                obj.heading = '';
                obj.scannerName = '';
                nameChangeVis = 'off';
                nameChangeEn = 'on';
                nameChangeColor = 'w';
            end
            
            ph = 1320;
            obj.minimumWidth = 836;
            obj.hPanel = uipanel('parent',[],'BorderType','none','units','pixels', 'position', [0 0 obj.minimumWidth ph]);
            
            pageTFlow = most.gui.uiflowcontainer('parent', obj.hPanel, 'flowdirection','lefttoright','margin',0.00001);
            most.gui.uipanel('parent',pageTFlow,'BorderType','none','units','pixels', 'WidthLimits',44);
            
            pageFlow = most.gui.uiflowcontainer('parent', pageTFlow, 'flowdirection','topdown','margin',0.00001);
            
            most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',26);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'SizeLimits',[349 22]);
            most.gui.staticText('parent', rowFlow,'VerticalAlignment','middle','HorizontalAlignment', 'left', 'String', 'Scanner Name','WidthLimits',96);
            obj.etName = most.gui.uicontrol('parent', rowFlow, 'Style', 'edit','HorizontalAlignment', 'left','enable',nameChangeEn,'backgroundcolor',nameChangeColor,'Bindings',{obj 'scannerName' 'string'});
            obj.nameStuff = most.gui.uipanel('parent',rowFlow,'BorderType','none','WidthLimits',12,'visible',nameChangeVis);%just to get the desired gap
            u = most.gui.uicontrol('parent', rowFlow,'String','Change','WidthLimits',60,'callback',@obj.changeName,'visible',nameChangeVis);
            obj.nameStuff(end+1) = u.hCtl;
            
            most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'VerticalAlignment','middle','HorizontalAlignment', 'left', 'String', 'Scanner Type','WidthLimits',96);
            most.gui.uicontrol('parent', rowFlow,'Style','popupmenu','WidthLimits',252,'Bindings',{obj 'scannerTypeSel' 'value'},'string',...
                {'Vidrio Technologies RMR Scanner' 'Resonant Scanning System (RG/RGG)' 'Linear Scanning System (GG)' 'Spatial Light Modulator (SLM)'});
            
        
            most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Signal Acquisition DAQ','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.pmAcqDaq = most.gui.popupMenuEdit('parent', rowFlow,'Bindings',{{obj 'acqDev' 'string'} {obj 'acqDevChoices' 'choices'}}, 'WidthLimits',150);
            
            
            % DigitalIODevicePopUp
            gap = most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Auxiliary Digital I/O DAQ','VerticalAlignment','middle','HorizontalAlignment', 'left', 'WidthLimits',200);
            obj.hDigitalIODevicePopUp = most.gui.popupMenuEdit('parent', rowFlow,'validationFunc',@obj.validateDaqChoice,'Bindings',{obj 'digIoDev' 'string'}, 'WidthLimits',150,...
                'TooltipString', 'Enter the Device name of the DAQ board that is used for digital inputs/outputs (triggers/clocks etc). It must be installed in the same PXI chassis as the FlexRIO Digitizer.');
            obj.vdaqHideSections = [gap rowFlow];
            
            
            % channel table
            most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            tableFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001,'HeightLimits',122);
            
            
            % ShutterTable
            rowFlow = most.gui.uiflowcontainer('parent', tableFlow, 'flowdirection','topdown', 'WidthLimits',240);
            most.gui.uicontrol('parent', rowFlow,'Style', 'text','String', 'Select shutters that must be open when using this scanner.', 'HorizontalAlignment', 'left','HeightLimits',16);
            obj.hShutterTable = uitable('parent', rowFlow,'Data', {false ''},'ColumnName', {'Select', 'Shutter Device'}, 'ColumnFormat', {'logical', 'char'}, ...
                'ColumnEditable', [true, false],'ColumnWidth', {50, 160},'RowName', [], 'RowStriping', 'Off');
            
            most.gui.uipanel('parent',tableFlow,'BorderType','none','units','pixels', 'WidthLimits',60);%just to get the desired gap
            
            rowFlow = most.gui.uiflowcontainer('parent', tableFlow, 'flowdirection','topdown', 'WidthLimits',240);
            most.gui.uicontrol('parent', rowFlow, 'Style', 'text', 'String', 'Indicate channels that have an inverted PMT signal.', 'HorizontalAlignment', 'left','HeightLimits',16);
            obj.hChannelTable = uitable('parent', rowFlow, 'ColumnName', {'AI Channel', 'Invert'},'ColumnFormat', {'char', 'logical'}, 'ColumnEditable', [false, true], ...
                'ColumnWidth', {100 50},'RowName', {}, 'Data', {},'RowStriping', 'Off');
            
            most.gui.uipanel('parent',tableFlow,'BorderType','none','units','pixels', 'WidthLimits',60);%just to get the desired gap
            
            rowFlow = most.gui.uiflowcontainer('parent', tableFlow, 'flowdirection','topdown', 'WidthLimits',240);
            most.gui.uicontrol('parent', rowFlow, 'Style', 'text', 'String', 'Select beams to modulate with this scanner.', 'HorizontalAlignment', 'left','HeightLimits',16);
            obj.hBeamTable = uitable('parent', rowFlow,'Data', {false ''},'ColumnName', {'Select', 'Beam'}, 'ColumnFormat', {'logical', 'char'}, ...
                'ColumnEditable', [true, false],'ColumnWidth', {50, 160},'RowName', [], 'RowStriping', 'Off','CellEditCallback',@obj.beamCellEditFcn);
            
            
            obj.slmStuff = most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24, 'visible','off');%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22, 'visible','off');
            most.gui.staticText('parent', rowFlow,'String', 'SLM Type','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            most.gui.popupMenuEdit('parent', rowFlow, 'WidthLimits',150,'Bindings',{{obj 'slmTpye' 'string'} {obj 'slmChoices' 'choices'}});
            obj.slmStuff(end+1) = rowFlow;
            
            
            obj.slmStuff(end+1) = most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24, 'visible','off');%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22, 'visible','off');
            most.gui.staticText('parent', rowFlow,'String', 'LUT Calibration DAQ','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hLutDevicePopUp = most.gui.popupMenuEdit('parent', rowFlow, 'WidthLimits',150,'Bindings',{obj 'lutDev' 'string'});
            obj.slmStuff(end+1) = rowFlow;
            
            obj.slmStuff(end+1) = most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24, 'visible','off');%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22, 'visible','off');
            most.gui.staticText('parent', rowFlow,'String', 'LUT Calibration Input Channel','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hLutChannelPopUp = most.gui.popupMenuEdit('parent', rowFlow, 'WidthLimits',150);
            obj.slmStuff(end+1) = rowFlow;
            
            obj.slmStuff(end+1) = most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24, 'visible','off');%just to get the desired gap            
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',24, 'visible','off');
            most.gui.staticText('parent', rowFlow,'String', 'Scanner Name','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            most.gui.popupMenuEdit('parent', rowFlow, 'WidthLimits',150,'Bindings',{{obj 'slmLinscanChoices' 'choices'} {obj 'slmLinScanner' 'string'}},...
                'Tooltip','If the SLM is in a beam path in series with scan mirrors, enter the associated scanner name (the scan mirrors should be configured separately as a another scanning system).');
            obj.slmStuff(end+1) = rowFlow;
            
            obj.slmStuff(end+1) = most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24, 'visible','off');%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22, 'visible','off');
            most.gui.staticText('parent', rowFlow,'String', 'Focal Length [mm]','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            most.gui.uicontrol('parent', rowFlow, 'WidthLimits',54,'style','edit','Tooltip','Focal Length of the image forming lens of the SLM in mm.','Bindings',{obj 'focalLength' 'value'});
            obj.slmStuff(end+1) = rowFlow;
            
            tooltip = sprintf('Refractive index of medium the SLM is operating in.\nTypically air (n = 1.000293)');
            obj.slmStuff(end+1) = most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24, 'visible','off');%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22, 'visible','off');
            most.gui.staticText('parent', rowFlow,'String', 'Refractive Index of SLM Medium','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            most.gui.uicontrol('parent', rowFlow, 'WidthLimits',54,'style','edit','Tooltip',tooltip,'Bindings',{obj 'slmMediumRefractiveIdx' 'value'});
            obj.slmStuff(end+1) = rowFlow;
            
            tooltip = sprintf('Refractive index of medium the objective is operating in.\nTypically water (n = 1.333) or air (n = 1.000293)');
            obj.slmStuff(end+1) = most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24, 'visible','off');%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22, 'visible','off');
            most.gui.staticText('parent', rowFlow,'String', 'Refractive Index of Objective Medium','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            most.gui.uicontrol('parent', rowFlow, 'WidthLimits',54,'style','edit','Tooltip',tooltip,'Bindings',{obj 'objectiveMediumRefractiveIdx' 'value'});
            obj.slmStuff(end+1) = rowFlow;
            
            obj.slmStuff(end+1) = most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24, 'visible','off');%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22, 'visible','off');
            most.gui.staticText('parent', rowFlow,'String', 'Zero Order Beam Block Radius','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            most.gui.uicontrol('parent', rowFlow, 'WidthLimits',54,'style','edit','Bindings',{obj 'zeroOrderBlockRadius' 'value'});
            obj.slmStuff(end+1) = rowFlow;
        
            % ResonantMirrorPanel 
            rph = 361;
            obj.hResSection = most.gui.uiflowcontainer('parent', pageFlow,'flowdirection','bottomup','margin',0.0001,'HeightLimits',rph + 30);
            obj.hResPanel = most.gui.uipanel('parent', obj.hResSection,'Title', 'Resonant Mirror Settings','Units', 'pixels','HeightLimits',rph,'WidthLimits',450);
            
            resTFlow = most.gui.uiflowcontainer('parent', obj.hResPanel,'flowdirection','lefttoright','margin',0.0001);
            most.gui.uipanel('parent',resTFlow,'BorderType','none','units','pixels', 'WidthLimits',44);
            resFlow = most.gui.uiflowcontainer('parent', resTFlow,'flowdirection','topdown','margin',0.0001);
        
            
            % NominalFrequencyEdit 
            most.gui.uipanel('parent',resFlow,'BorderType','none','units','pixels', 'HeightLimits',16);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', resFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',20);
            most.gui.staticText('parent', rowFlow,'String', 'Scanner Frequency (Hz)','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hNominalFrequencyEdit = most.gui.uicontrol('parent', rowFlow,'Style', 'edit', 'String', '7910','HorizontalAlignment', 'center', 'WidthLimits',50);
        
            
            % ResZoomDevicePopUp 
            obj.vdaqHideSections(end+1) = most.gui.uipanel('parent',resFlow,'BorderType','none','units','pixels', 'HeightLimits',16);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', resFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Zoom Control DAQ','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hResZoomDevicePopUp = most.gui.popupMenuEdit('parent', rowFlow, 'validationFunc',@obj.validateZoomDaqChoice,'Bindings',{obj 'zoomCtlDaq' 'string'}, 'WidthLimits',150);
            obj.vdaqHideSections(end+1) = rowFlow;
        
            
            % resonantSyncInputTerminal 
            obj.vdaqShowSections = most.gui.uipanel('parent',resFlow,'BorderType','none','units','pixels', 'HeightLimits',16);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', resFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Sync Pulse Input Terminal','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hResSyncTermPopUp = most.gui.popupMenuEdit('parent', rowFlow, 'WidthLimits',50, 'TooltipString', 'Digital input channel to which the scanner sync pulse is connected.');
            obj.vdaqShowSections(end+1) = rowFlow;
            
            % ResZoomChannelIDPopUp 
            most.gui.uipanel('parent',resFlow,'BorderType','none','units','pixels', 'HeightLimits',16);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', resFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Zoom Control Channel ID','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hResZoomChannelIDPopUp = most.gui.popupMenuEdit(...
                'parent', rowFlow, 'WidthLimits',50, ...
                'TooltipString', 'Analog Output channel ID to be used to control the Resonant Scanner Zoom level.');
            
            
        
            % ResZoomChannelIDPopUp 
            most.gui.uipanel('parent',resFlow,'BorderType','none','units','pixels', 'HeightLimits',16);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', resFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Scanner Enable DO Channel (optional)','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hResEnableTerminalPopUp = most.gui.popupMenuEdit('parent', rowFlow,'WidthLimits',50, 'TooltipString', ...
                'Digital Output Terminal to be used to enable/disable the Resonant Scanner.\nNote: the digital terminal is on the DAQ board hosting the resonant zoom analog output.');            
        
            
            obj.nonRmrStuff = most.gui.uipanel('parent',resFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', resFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Zoom Control Max Command (V)','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hResMaxVoltageCmdEdit = most.gui.uicontrol('parent', rowFlow, 'Style', 'edit', 'String', '5','HorizontalAlignment', 'center','WidthLimits',50, ...
                'TooltipString', 'Voltage command that sets the resonant scanner to the maximum angular range. 5V for most resonant scanners.');
            obj.nonRmrStuff(end+1) = rowFlow;
        
            obj.nonRmrStuff(end+1) = most.gui.uipanel('parent',resFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', resFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Max Angular Range (optical deg pk-pk)','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            % ResMaxAngularRangeEdit 
            obj.hResMaxAngularRangeEdit = most.gui.uicontrol('parent', rowFlow, 'Tag', 'ResMaxAngularRangeEdit', 'Style', 'edit', 'HorizontalAlignment', 'center','WidthLimits',50, 'Bindings', {obj 'resAngularRange' 'value'});
            obj.nonRmrStuff(end+1) = rowFlow;
        
            
            % ResSettlingTimeEdit 
            most.gui.uipanel('parent',resFlow,'BorderType','none','units','pixels', 'HeightLimits',16);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', resFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Zoom Amplitude Settling Time (sec)','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hResSettlingTimeEdit = most.gui.uicontrol('parent', rowFlow,'Tag', 'ResSettlingTimeEdit','Style', 'edit','String', '.5','WidthLimits',50,'HorizontalAlignment', 'center', ...
                'TooltipString', 'Time to wait for the resonant scanner to reach its desired frequency after an update of the zoom Factor');
        
            
            
            % GalvoPanel
            gph = 485;
            obj.hGalvoSection = most.gui.uiflowcontainer('parent', pageFlow,'flowdirection','bottomup','margin',0.0001,'HeightLimits',gph + 30);
            obj.hGalvoPanel = most.gui.uipanel('parent', obj.hGalvoSection,'Title', 'Galvo Mirror Settings','HeightLimits',gph,'WidthLimits',810);
            gTFlow = most.gui.uiflowcontainer('parent', obj.hGalvoPanel,'flowdirection','topdown','margin',0.0001);
            
            obj.galvoDaqFlow = most.gui.uiflowcontainer('parent', gTFlow,'flowdirection','lefttoright','HeightLimits', 70);
            most.gui.uipanel('parent', gTFlow,'BorderType','none','HeightLimits',20);
            obj.vdaqHideSections(end+1) = obj.galvoDaqFlow;
            
            
            dg = 80;
            
            most.gui.uipanel('parent',obj.galvoDaqFlow,'BorderType','none','units','pixels', 'WidthLimits',40);
            colFlow = most.gui.uiflowcontainer('parent', obj.galvoDaqFlow,'flowdirection','bottomup','WidthLimits',180);
            obj.hGalvoCtlDaqPopUp = most.gui.popupMenuEdit('parent', colFlow,'TooltipString', 'NI DAQ board for controlling the X/Y galvos.', 'Bindings', {obj 'galvoDaq' 'string'},'HeightLimits',22);
            most.gui.uicontrol('parent', colFlow,'Style', 'text', 'String', 'Galvo Position Control DAQ', 'HorizontalAlignment', 'left', 'TooltipString', 'DAQ board for controlling the X/Y galvos.', 'HeightLimits',16);
            
            
            most.gui.uipanel('parent',obj.galvoDaqFlow,'BorderType','none','units','pixels', 'WidthLimits',dg);
            colFlow = most.gui.uiflowcontainer('parent', obj.galvoDaqFlow,'flowdirection','bottomup','WidthLimits',180);
            obj.hGalvoFdbkDaqPopUp = most.gui.popupMenuEdit('parent', colFlow,'TooltipString', 'DAQ board for reading the position of the X/Y galvos.', 'Bindings', {obj 'galvoFeedbackDaq' 'string'},'HeightLimits',22);
            most.gui.uicontrol('parent', colFlow,'Style', 'text', 'String', 'Galvo Position Feedback DAQ', 'HorizontalAlignment', 'left','TooltipString', 'DAQ board for reading the position of the X/Y galvos.', 'HeightLimits',16);
            
            
            most.gui.uipanel('parent',obj.galvoDaqFlow,'BorderType','none','units','pixels', 'WidthLimits',dg);
            colFlow = most.gui.uiflowcontainer('parent', obj.galvoDaqFlow,'flowdirection','bottomup','WidthLimits',180);
            obj.hOffsetDaqPopUp = most.gui.popupMenuEdit('parent', colFlow,'TooltipString', 'DAQ board for controlling the position offset of the X/Y galvos.', 'Bindings', {obj 'galvoOffsetDaq' 'string'},'HeightLimits',22);
            most.gui.uicontrol('parent', colFlow,'Style', 'text', 'String', 'Galvo Position Offset DAQ', 'HorizontalAlignment', 'left','TooltipString', 'DAQ board for controlling the position offset of the X/Y galvos.', 'HeightLimits',16);
            
            
            xygph = 350;
            gxyFlow = most.gui.uiflowcontainer('parent', gTFlow,'flowdirection','lefttoright','margin',0.0001);
            most.gui.uipanel('parent',gxyFlow,'BorderType','none','units','pixels', 'WidthLimits',44);
            
            obj.hXGalvoPanel = most.gui.uipanel('parent', gxyFlow,'Title', 'X Galvo','SizeLimits', [332 xygph]);
            xgTFlow = most.gui.uiflowcontainer('parent', obj.hXGalvoPanel, 'flowdirection','lefttoright','margin',0.00001);
            most.gui.uipanel('parent',xgTFlow,'BorderType','none','units','pixels', 'WidthLimits',44);
            xgFlow = most.gui.uiflowcontainer('parent', xgTFlow, 'flowdirection','topdown','margin',0.00001);
            
            most.gui.uipanel('parent',gxyFlow,'BorderType','none','units','pixels', 'WidthLimits',44);
            obj.hYGalvoPanel = most.gui.uipanel('parent', gxyFlow,'Title', 'Y Galvo','SizeLimits', [332 xygph]);
            ygTFlow = most.gui.uiflowcontainer('parent', obj.hYGalvoPanel, 'flowdirection','lefttoright','margin',0.00001);
            most.gui.uipanel('parent',ygTFlow,'BorderType','none','units','pixels', 'WidthLimits',44);
            ygFlow = most.gui.uiflowcontainer('parent', ygTFlow, 'flowdirection','topdown','margin',0.00001);
            

            % XGalvoAnalogOutputChannelIDText
            most.gui.uipanel('parent',xgFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', xgFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Position Control AO Channel ID','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hXGalvoAnalogOutputChannelIDPopUp = most.gui.popupMenuEdit('parent', rowFlow,'WidthLimits',50,'Bindings',{obj 'xGalvoChanSel' 'string'});
            
            % XGalvoMaxAngularRangeEdit
            obj.nonRmrStuff(end+1) = most.gui.uipanel('parent',xgFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', xgFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Max Angular Range (optical deg pk-pk)','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hXGalvoMaxAngularRangeEdit = most.gui.uicontrol('parent', rowFlow,'Style', 'edit', 'String', '15','HorizontalAlignment', 'center', 'WidthLimits',50, 'Bindings', {obj 'xgalvoAngularRange' 'value'});
            obj.nonRmrStuff(end+1) = rowFlow;
        
            % XGalvoOpticalConversionFactorText
            obj.nonRmrStuff(end+1) = most.gui.uipanel('parent',xgFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', xgFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Command Scaling Factor (V/optical deg)','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hXGalvoOpticalConversionFactorEdit = most.gui.uicontrol('parent', rowFlow,'Style', 'edit', 'String', '1','HorizontalAlignment', 'center', 'WidthLimits',50);
            obj.nonRmrStuff(end+1) = rowFlow;
        
            % XGalvoParkAngleText
            obj.nonRmrStuff(end+1) = most.gui.uipanel('parent',xgFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', xgFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Park Angle (optical deg)','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hXGalvoParkAngleEdit = most.gui.uicontrol('parent', rowFlow,'Style', 'edit', 'String', '-8','HorizontalAlignment', 'center', 'WidthLimits',50);
            obj.nonRmrStuff(end+1) = rowFlow;

            % 
            most.gui.uipanel('parent',xgFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', xgFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Position Feedback AI Channel ID','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hXGalvoInputChannelIDPopUp = most.gui.popupMenuEdit('parent', rowFlow,'WidthLimits',50);
            most.gui.uipanel('parent',xgFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap

            % XGalvoAnalogOutputChannelIDText
            rowFlow = most.gui.uiflowcontainer('parent', xgFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            obj.offsetStuff = rowFlow;
            most.gui.staticText('parent', rowFlow,'String', 'Position Offset AO Channel ID','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hXGalvoAnalogOutputOffsetPopUp = most.gui.popupMenuEdit('parent', rowFlow,'WidthLimits',50);
            obj.offsetStuff(end+1) = most.gui.uipanel('parent',xgFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap

            % 
            rowFlow = most.gui.uiflowcontainer('parent', xgFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Max Position Offset Cmd (V)','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hXGalvoMaximumVoltageOutputEdit = most.gui.uicontrol('parent', rowFlow,'Style', 'edit', 'String', '1','HorizontalAlignment', 'center', 'WidthLimits',50);
            obj.offsetStuff(end+1) = rowFlow;
            obj.offsetStuff(end+1) = most.gui.uipanel('parent',xgFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap;

            % hXGalvoExtendedFov
            obj.extendedStuff = most.gui.uiflowcontainer('parent', xgFlow, 'flowdirection','topdown','margin',0.00001);
            obj.hXGalvoExtendedFov = most.gui.uicontrol('parent', obj.extendedStuff,'style','checkbox','String', 'Extended Resonant FOV (default)','HeightLimits',22,'callback',@obj.extendedFovModeSet, 'Bindings', {obj 'extendedFov' 'value'});
            most.gui.uipanel('parent',obj.extendedStuff,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            
            
            % YGalvoAnalogOutputChannelIDText
            most.gui.uipanel('parent',ygFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', ygFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Position Control AO Channel ID','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hYGalvoAnalogOutputChannelIDPopUp = most.gui.popupMenuEdit('parent', rowFlow,'WidthLimits',50);
            

            % YGalvoMaxAngularRangeEdit
            obj.nonRmrStuff(end+1) = most.gui.uipanel('parent',ygFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', ygFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Max Angular Range (optical deg pk-pk)','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hYGalvoMaxAngularRangeEdit = most.gui.uicontrol('parent', rowFlow,'Style', 'edit', 'String', '15','HorizontalAlignment', 'center', 'WidthLimits',50);
            obj.nonRmrStuff(end+1) = rowFlow;
        
            % YGalvoOpticalConversionFactorText
            obj.nonRmrStuff(end+1) = most.gui.uipanel('parent',ygFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', ygFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Command Scaling Factor (V/optical deg)','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hYGalvoOpticalConversionFactorEdit = most.gui.uicontrol('parent', rowFlow,'Style', 'edit', 'String', '1','HorizontalAlignment', 'center', 'WidthLimits',50);
            obj.nonRmrStuff(end+1) = rowFlow;
        
            % YGalvoParkAngleText
            obj.nonRmrStuff(end+1) = most.gui.uipanel('parent',ygFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', ygFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Park Angle (optical deg)','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hYGalvoParkAngleEdit = most.gui.uicontrol('parent', rowFlow,'Style', 'edit', 'String', '-8','HorizontalAlignment', 'center', 'WidthLimits',50);
            obj.nonRmrStuff(end+1) = rowFlow;

            % YGalvoAnalogOutputChannelIDText
            most.gui.uipanel('parent',ygFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', ygFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Position Feedback AI Channel ID','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hYGalvoInputChannelIDPopUp = most.gui.popupMenuEdit('parent', rowFlow,'WidthLimits',50);

            % YGalvoAnalogOutputChannelIDText
            obj.offsetStuff(end+1) = most.gui.uipanel('parent',ygFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', ygFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Position Offset AO Channel ID','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hYGalvoAnalogOutputOffsetPopUp = most.gui.popupMenuEdit('parent', rowFlow,'WidthLimits',50);
            obj.offsetStuff(end+1) = rowFlow;

            % YGalvoMaxAngularRangeText
            obj.offsetStuff(end+1) = most.gui.uipanel('parent',ygFlow,'BorderType','none','units','pixels', 'HeightLimits',24);%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', ygFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22);
            most.gui.staticText('parent', rowFlow,'String', 'Max Position Offset Cmd (V)','VerticalAlignment','middle','HorizontalAlignment', 'left','WidthLimits',200);
            obj.hYGalvoMaximumVoltageOutputEdit = most.gui.uicontrol('parent', rowFlow,'Style', 'edit', 'String', '1','HorizontalAlignment', 'center', 'WidthLimits',50);
            obj.offsetStuff(end+1) = rowFlow;
            
            
            obj.hAdvButtonPanel = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','topdown','margin',0.00001, 'HeightLimits',66);
            most.gui.uipanel('parent',obj.hAdvButtonPanel,'BorderType','none','units','pixels', 'HeightLimits',40);%just to get the desired gap
            most.gui.uicontrol('parent',obj.hAdvButtonPanel,'units','pixels','WidthLimits',200,'string','Show Advanced Settings...','callback',@obj.showAdvanced);
            
            
            obj.advancedStuff = most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24, 'visible','off');%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22,'visible','off');
            most.gui.staticText('parent', rowFlow,'String', 'Custom Signal Conditioning Option','VerticalAlignment','middle','HorizontalAlignment', 'left', 'WidthLimits',200);
            obj.hCutomSignalCondPopup = most.gui.popupMenuEdit('parent', rowFlow,'WidthLimits', 150);
            obj.advancedStuff(end+1) = rowFlow;
            
            
            % UseExternalSampleClockCheckBox
            obj.advancedStuff(end+1) = most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24, 'visible','off');%just to get the desired gap
            u = most.gui.uicontrol('parent', pageFlow, 'Style', 'checkbox', 'String', 'Use External Sample Clock','Bindings', {obj 'useExtClk' 'value'}, 'visible','off',...  
                'TooltipString', 'Check if you want to use the external sample clock connected to the CLK IN terminal of the FlexRIO digitizer module.', 'SizeLimits',[160 24]);
            obj.advancedStuff(end+1) = u.hCtl;
            
        
        
            % ExternalSampleClockRateText
            obj.advancedStuff(end+1) = most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24, 'visible','off');%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22,'visible','off');
            most.gui.staticText('parent', rowFlow,'String', 'External Sample Clock Rate (Hz)','VerticalAlignment','middle','HorizontalAlignment', 'left', 'WidthLimits',200);
            obj.hExternalSampleClockRateEdit = most.gui.uicontrol('parent', rowFlow,'WidthLimits', 80, 'Style', 'edit', ...
                'TooltipString', 'Enter the nominal frequency of the external sample clock connected  to the CLK IN terminal (e.g. 80e6). The actual rate is measured on FPGA.');
            obj.advancedStuff(end+1) = rowFlow;
            
            
            obj.advancedStuff(end+1) = most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24, 'visible','off');%just to get the desired gap
            u = most.gui.uicontrol('parent', pageFlow, 'Style', 'checkbox', 'String', 'Export 10MHz Reference Clock','Bindings', {obj 'exprtClk' 'value'}, 'visible','off',...  
                'TooltipString', 'Check if you want to export a 10MHz reference clock on PFI14 of the aux digital IO DAQ.', 'SizeLimits',[260 24]);
            obj.advancedStuff(end+1) = u.hCtl;
        
            
            
            obj.advancedStuff(end+1) = most.gui.uipanel('parent',pageFlow,'BorderType','none','units','pixels', 'HeightLimits',24, 'visible','off');%just to get the desired gap
            rowFlow = most.gui.uiflowcontainer('parent', pageFlow, 'flowdirection','lefttoright','margin',0.00001, 'HeightLimits',22,'visible','off');
            most.gui.staticText('parent', rowFlow,'String', 'Laser Clock Port','VerticalAlignment','middle','HorizontalAlignment', 'left', 'WidthLimits',150);
            obj.hLaserPortPop = most.gui.popupMenuEdit('parent', rowFlow,'WidthLimits', 60, 'TooltipString', 'Digital input where laser trigger is connected.');
            obj.advancedStuff(end+1) = rowFlow;
            
            
            obj.hConfigEditor.addSimRio();
            obj.reload();
        end
        
        function changeName(obj,varargin)
            newName = inputdlg('Enter a new name for the scanner. Note, changing the scanner name will reset associated calibration data such as line phase and optical alignment.','Change Scanner Name',1,{obj.scannerName});
            if ~isempty(newName) && ~strcmp(newName{1},obj.scannerName)
                obj.scannerName = newName{1};
            end
        end
        
        function applySmartDefaultSettings(varargin)
        end
        
        function refreshPageDependentOptions(obj)
            oldTableDat = obj.hShutterTable.Data;
            if numel(oldTableDat) > 1
                selectedShutters = oldTableDat([oldTableDat{:,1}],2);
            else
                selectedShutters = [];
            end
            
            shutters = obj.hConfigEditor.shutterNames;
            if numel(shutters)
                shutterDat = [repmat({false},numel(shutters),1) shutters];
            
                if ~isempty(selectedShutters)
                    shutterDat(:,1) = num2cell(ismember(shutters,selectedShutters));
                end
                
                obj.hShutterTable.Data = shutterDat;
            else
                obj.hShutterTable.Data = {};
            end
            
            
            oldTableDat = obj.hBeamTable.Data;
            if numel(oldTableDat) > 1
                selectedBeams = oldTableDat([oldTableDat{:,1}],2);
            else
                selectedBeams = [];
            end
            
            beams = obj.hConfigEditor.beams;
            if numel(beams)
                beamDat = [repmat({false},size(beams,1),1) beams(:,1)];
                
                if ~isempty(selectedBeams)
                    beamDat(:,1) = num2cell(ismember(beams(:,1),selectedBeams));
                end
                
                obj.hBeamTable.Data = beamDat;
            else
                obj.hBeamTable.Data = {};
            end
            
            
            obj.hResZoomDevicePopUp.choices = obj.hConfigEditor.availableDaqs;
            obj.hGalvoFdbkDaqPopUp.choices = [{''}; obj.hConfigEditor.availableDaqs([obj.hConfigEditor.daqInfo.isXSer])];
            obj.hOffsetDaqPopUp.choices = [{''}; obj.hConfigEditor.availableDaqs];
            
            if isempty(obj.hConfigEditor.hSlmRegistry)
                obj.slmChoices = {};
            else
                vs = obj.hConfigEditor.hSlmRegistry.values;
                vs = [vs{:}];
                obj.slmChoices = unique({vs.DisplayName});
            end
            
            scannerNames = obj.hConfigEditor.scannerNames()';
            obj.slmLinscanChoices = [{'None'} scannerNames(obj.hConfigEditor.scannerCanLinearScan)];
            
            obj.hLutDevicePopUp.choices = [{''}; obj.hConfigEditor.availableDaqs];
        end
        
        function reload(obj)
            newScanner = isempty(obj.scannerName);
            if newScanner
                obj.listLabel = 'Scanner Settings (New Scanner)';
                txt = 'Configure DAQ and scanning properties for the';
            else
                obj.listLabel = ['Scanner Settings (' obj.scannerName ')'];
                txt = ['Configure DAQ and scanning properties for the ''' obj.scannerName ''''];
            end
            
            obj.descriptionText = [txt ' scanning system. Give the scanner a unique name and specify the scanner type. Previously configured beam DAQs and shutters can be assigned to this scanner.'];
            
            obj.refreshPageDependentOptions();
            
            
            if newScanner
                scannerNames = obj.hConfigEditor.scannerNames()';
                if ~ismember('ImagingScanner', scannerNames)
                    obj.scannerName = 'ImagingScanner';
                else
                    nf = cellfun(@(s)strncmpi(s, 'scanner', 7) && (length(s) > 7) && ~isnan(str2double(s(8:end))),scannerNames);
                    if any(nf)
                        num = max(str2double(strrep(lower(scannerNames(nf)),'scanner',''))) + 1;
                    else
                        num = numel(scannerNames) + 1;
                    end
                    obj.scannerName = sprintf('Scanner%d',num);
                end
                
                obj.defaultExtendedFov = true;
                
                if ~isempty(obj.hConfigEditor.availableRios)
                    isVdaq = cellfun(@dabs.vidrio.rdi.Device.isRdiDeviceName,obj.hConfigEditor.availableRios);
                    if any(isVdaq)
                        obj.acqDev = obj.hConfigEditor.availableRios{find(isVdaq,1)};
                        obj.scannerType = 'rmr';
                        obj.xGalvoChanSel = 'AO0';
                        obj.hYGalvoAnalogOutputChannelIDPopUp.string = 'AO1';
                        obj.hResZoomChannelIDPopUp.string = 'AO4';
                        obj.hXGalvoInputChannelIDPopUp.string = 'AI0';
                        obj.hYGalvoInputChannelIDPopUp.string = 'AI1';
                    else
                        rio = obj.hConfigEditor.availableRios{1};
                        obj.acqDev = rio;
                        pxiN = obj.hConfigEditor.rioInfo.(rio).pxiNumber;
                        
                        if ~isempty(obj.hConfigEditor.daqInfo)
                            dq = find(([obj.hConfigEditor.daqInfo.pxiNum] == pxiN) & [obj.hConfigEditor.daqInfo.isXSer],1);
                            if ~isempty(dq)
                                obj.digIoDev = obj.hConfigEditor.availableDaqs{dq};
                                obj.galvoDaq = obj.hConfigEditor.availableDaqs{dq};
                                
                                Nd = numel(obj.hConfigEditor.availableDaqs);
                                if Nd > 1
                                    inds = 1:Nd;
                                    inds(dq) = [];
                                    
                                    obj.zoomCtlDaq = obj.hConfigEditor.availableDaqs{inds(1)};
                                    obj.scannerType = 'rmr';
                                    obj.xGalvoChanSel = 'AO0';
                                    obj.hYGalvoAnalogOutputChannelIDPopUp.string = 'AO1';
                                    obj.hResZoomChannelIDPopUp.string = 'AO1';
                                    obj.hXGalvoInputChannelIDPopUp.string = 'AI0';
                                    obj.hYGalvoInputChannelIDPopUp.string = 'AI1';
                                else
                                    obj.zoomCtlDaq = obj.hConfigEditor.availableDaqs{dq};
                                    obj.scannerType = 'resonant';
                                    obj.xGalvoChanSel = 'None';
                                    obj.hYGalvoAnalogOutputChannelIDPopUp.string = 'AO1';
                                    obj.hResZoomChannelIDPopUp.string = 'AO0';
                                end
                            else
                                obj.scannerType = 'rmr';
                            end
                        else
                            obj.scannerType = 'rmr';
                        end
                    end
                elseif  ~isempty(obj.hConfigEditor.daqInfo)
                    % find a simultaneous sampling daq
                    obj.scannerType = 'linear';
                else
                    obj.acqDev = 'vDAQ0';
                    obj.scannerType = 'rmr';
                    obj.xGalvoChanSel = 'AO0';
                    obj.hYGalvoAnalogOutputChannelIDPopUp.string = 'AO1';
                    obj.hResZoomChannelIDPopUp.string = 'AO4';
                    obj.hXGalvoInputChannelIDPopUp.string = 'AI0';
                    obj.hYGalvoInputChannelIDPopUp.string = 'AI1';
                end
            else
                if isempty(obj.heading)
                    return;
                end
                mdfData = obj.getCurrentMdfDataStruct();
                c = regexp(obj.heading,'(.*)\(.*\)','tokens');
                s2dType = strtrim(c{1}{1});
                
                obj.internalSet = true;
                switch s2dType
                    case 'ResScan'
                        if isfield(mdfData, 'scanheadModel') && strcmp(mdfData.scanheadModel, 'rmr')
                            obj.scannerType = 'rmr';
                        else
                            obj.scannerType = 'resonant';
                        end
                        
                    case 'LinScan'
                        obj.scannerType = 'linear';
                        
                    case 'SlmScan'
                        obj.scannerType = 'slm';
                        
                    case 'RggScan'
                        if isfield(mdfData, 'scanheadModel') && strcmp(mdfData.scanheadModel, 'rmr')
                            obj.scannerType = 'rmr';
                        elseif isempty(mdfData.resonantAngularRange)
                            obj.scannerType = 'linear';
                        else
                            obj.scannerType = 'resonant';
                        end
                end
                obj.internalSet = false;
                
                setFromDifferentNames('acqDev','rioDeviceID','deviceNameAcq','acquisitionDeviceId');
                setFromDifferentNames('digIoDev','digitalIODeviceName','deviceNameAux');
                
                if ~obj.acqDevIsRdi
                    if ~obj.aisFixed && isfield(mdfData, 'channelIDs')
                        chIds = 0:obj.numChans-1;
                        ns = 1:min(numel(mdfData.channelIDs),obj.numChans);
                        chIds(ns) = mdfData.channelIDs(ns);
                        obj.hChannelTable.Data(:,1) = arrayfun(@(x)sprintf('  AI%d',x),chIds,'uniformoutput',false);
                    end
                    
                    if isfield(mdfData, 'deviceNameGalvoFeedback')
                        obj.galvoFeedbackDaq = mdfData.deviceNameGalvoFeedback;
                    else
                        obj.galvoFeedbackDaq = '';
                    end
                    
                    if isfield(mdfData, 'galvoDeviceName')
                        if ~isempty(mdfData.galvoDeviceName) && ~obj.acqDevIsRdi
                            obj.galvoDaq = mdfData.galvoDeviceName;
                        end
                    elseif isfield(mdfData, 'deviceNameGalvo')
                        obj.galvoDaq = mdfData.deviceNameGalvo;
                    end
                    
                    if isfield(mdfData, 'deviceNameOffset')
                        obj.galvoOffsetDaq = mdfData.deviceNameOffset;
                    else
                        obj.galvoOffsetDaq = '';
                    end
                end
                
                mdfData.shutterIDs(mdfData.shutterIDs > obj.hConfigEditor.numShutters) = [];
                obj.hShutterTable.Data(:,1) = {false};
                obj.hShutterTable.Data(mdfData.shutterIDs,1) = {true};
                
                mdfData.channelsInvert(end+1:obj.numChans) = mdfData.channelsInvert(1);
                mdfData.channelsInvert(obj.numChans+1:end) = [];
                obj.hChannelTable.Data(:,2) = num2cell(mdfData.channelsInvert(:));
                
                numBeams = size(obj.hBeamTable.Data,1);
                beamEnable = repmat({false},numBeams,1);
                
                if obj.acqDevIsRdi
                    if isfield(mdfData,'beamIds')
                        beamEnable(mdfData.beamIds,1) = {true};
                    end
                else
                    if isfield(mdfData,'beamDaqID') && ~isempty(mdfData.beamDaqID) && mdfData.beamDaqID <= obj.hConfigEditor.numBeamDaqs
                        beamEnable = cellfun(@(daqId){daqId==mdfData.beamDaqID},obj.hConfigEditor.beams(:,2));
                    end
                end
                
                obj.hBeamTable.Data(:,1) = beamEnable;
                
                if isfield(mdfData,'extendedRggFov') && ~isempty(mdfData.extendedRggFov)
                    obj.extendedFov = mdfData.extendedRggFov;
                    obj.defaultExtendedFov = false;
                else
                    obj.defaultExtendedFov = true;
                end
                
                if isfield(mdfData,'nominalResScanFreq')
                    obj.hNominalFrequencyEdit.String = mdfData.nominalResScanFreq;
                end
                
                if isfield(mdfData, 'customSigCondOption') && ~isempty(mdfData.customSigCondOption)
                    obj.hCutomSignalCondPopup.string = mdfData.customSigCondOption;
                else
                    obj.hCutomSignalCondPopup.string = '';
                end
                
                setFromDifferentNames('useExtClk','externalSampleClock');
                if isfield(mdfData,'externalSampleClockRate')
                    obj.hExternalSampleClockRateEdit.String = mdfData.externalSampleClockRate;
                end
                
                if isfield(mdfData,'enableRefClkOutput')
                    obj.exprtClk = mdfData.enableRefClkOutput;
                else
                    obj.exprtClk = false;
                end
                
                if isfield(mdfData,'resonantZoomDeviceName')
                    if ~obj.acqDevIsRdi
                        if isempty(mdfData.resonantZoomDeviceName)
                            obj.zoomCtlDaq = mdfData.galvoDeviceName;
                        else
                            obj.zoomCtlDaq = mdfData.resonantZoomDeviceName;
                        end
                    end
                
                    if ischar(mdfData.resonantZoomAOChanID)
                        str = mdfData.resonantZoomAOChanID;
                    else
                        str = sprintf('AO%d',mdfData.resonantZoomAOChanID);
                    end
                    obj.hResZoomChannelIDPopUp.string = str;
                     
                    obj.resAngularRange = mdfData.resonantAngularRange;
                    
                    v = mdfData.rScanVoltsPerOpticalDegree*mdfData.resonantAngularRange;
                    obj.hResMaxVoltageCmdEdit.String = round(v*1000)/1000;
                    
                    obj.hResSettlingTimeEdit.String = mdfData.resonantScannerSettleTime;
                end
                
                if ~isfield(mdfData,'resonantEnableTerminal') || isempty(mdfData.resonantEnableTerminal)
                    obj.hResEnableTerminalPopUp.string = '';
                elseif isnumeric(mdfData.resonantEnableTerminal)
                    obj.hResEnableTerminalPopUp.string = sprintf('PFI%d',mdfData.resonantEnableTerminal);
                else
                    obj.hResEnableTerminalPopUp.string = mdfData.resonantEnableTerminal;
                end
                
                if isfield(mdfData,'resonantSyncInputTerminal') && ~isempty(mdfData.resonantSyncInputTerminal)
                    obj.hResSyncTermPopUp.string = mdfData.resonantSyncInputTerminal;
                else
                    obj.hResSyncTermPopUp.string = 'D1.0';
                end
                
                fName = chooseFieldName('galvoAOChanIDX','XMirrorChannelID');
                if ~isempty(fName)
                    if isempty(mdfData.(fName))
                        obj.xGalvoChanSel = 'None';
                    else
                        obj.xGalvoChanSel = sprintf('AO%d',mdfData.(fName));
                    end
                end
                
                if isfield(mdfData,'xGalvoAngularRange')
                    obj.xgalvoAngularRange = mdfData.xGalvoAngularRange;
                    
                    fName = chooseFieldName('galvoVoltsPerOpticalDegreeX','voltsPerOpticalDegreeX');
                    obj.hXGalvoOpticalConversionFactorEdit.String = mdfData.(fName);
                    
                    fName = chooseFieldName('galvoParkDegreesX','scanParkAngleX');
                    obj.hXGalvoParkAngleEdit.String = mdfData.(fName);
                    
                    fName = chooseFieldName('galvoAOChanIDY','YMirrorChannelID');
                    v = mdfData.(fName);
                    if isempty(v)
                        obj.hYGalvoAnalogOutputChannelIDPopUp.string = '';
                    else
                        obj.hYGalvoAnalogOutputChannelIDPopUp.string = sprintf('AO%d',v);
                    end
                    
                    obj.hYGalvoMaxAngularRangeEdit.String = mdfData.yGalvoAngularRange;
                    
                    fName = chooseFieldName('galvoVoltsPerOpticalDegreeY','voltsPerOpticalDegreeY');
                    obj.hYGalvoOpticalConversionFactorEdit.String = mdfData.(fName);
                    
                    fName = chooseFieldName('galvoParkDegreesY','scanParkAngleY');
                    obj.hYGalvoParkAngleEdit.String = mdfData.(fName);
                    
                    if isfield(mdfData,'XMirrorPosChannelID') && ~isempty(mdfData.XMirrorPosChannelID)
                        s = sprintf('AI%d',mdfData.XMirrorPosChannelID);
                        if isfield(mdfData,'XMirrorPosTermCfg') && ~isempty(mdfData.XMirrorPosTermCfg) && ~strcmp(mdfData.XMirrorPosTermCfg, 'Differential')
                            s = [s ' ' mdfData.XMirrorPosTermCfg];
                        end
                        obj.hXGalvoInputChannelIDPopUp.string = s;
                    elseif isfield(mdfData,'galvoAIChanIDX') && ~isempty(mdfData.galvoAIChanIDX) && ~isnan(mdfData.galvoAIChanIDX)
                        obj.hXGalvoInputChannelIDPopUp.string = sprintf('AI%d',mdfData.galvoAIChanIDX);
                    else
                        obj.hXGalvoInputChannelIDPopUp.string = '';
                    end
                    
                    if isfield(mdfData,'YMirrorPosChannelID') && ~isempty(mdfData.YMirrorPosChannelID)
                        s = sprintf('AI%d',mdfData.YMirrorPosChannelID);
                        if isfield(mdfData,'YMirrorPosTermCfg') && ~isempty(mdfData.YMirrorPosTermCfg) && ~strcmp(mdfData.YMirrorPosTermCfg, 'Differential')
                            s = [s ' ' mdfData.YMirrorPosTermCfg];
                        end
                        obj.hYGalvoInputChannelIDPopUp.string = s;
                    elseif isfield(mdfData,'galvoAIChanIDY') && ~isempty(mdfData.galvoAIChanIDY) && ~isnan(mdfData.galvoAIChanIDY)
                        obj.hYGalvoInputChannelIDPopUp.string = sprintf('AI%d',mdfData.galvoAIChanIDY);
                    else
                        obj.hYGalvoInputChannelIDPopUp.string = '';
                    end
                end
                
                if isfield(mdfData,'LaserTriggerPort')
                    obj.hLaserPortPop.string = mdfData.LaserTriggerPort;
                else
                    obj.hLaserPortPop.string = '';
                end
                
                if isfield(mdfData,'slmType')
                    if ~isempty(mdfData.slmType)
                        obj.slmTpye = obj.hConfigEditor.hSlmRegistry(lower(mdfData.slmType)).DisplayName;
                    else
                        obj.slmTpye = 'Generic Monitor SLM';
                    end
                    
                    v = mdfData.linearScannerName;
                    if isempty(v)
                        v = 'None';
                    end
                    obj.slmLinScanner = v;
                    
                    obj.focalLength = mdfData.focalLength;
                    
                    if isfield(mdfData,'slmMediumRefractiveIdx')
                        obj.slmMediumRefractiveIdx = mdfData.slmMediumRefractiveIdx;
                    end
                    
                    if isfield(mdfData,'objectiveMediumRefractiveIdx')
                        obj.objectiveMediumRefractiveIdx = mdfData.objectiveMediumRefractiveIdx;
                    end
                    
                    obj.zeroOrderBlockRadius = mdfData.zeroOrderBlockRadius;
                    
                    obj.lutDev = mdfData.lutCalibrationDaqDevice;
                    if isempty(mdfData.lutCalibrationChanID)
                        obj.hLutChannelPopUp.string = '';
                    else
                        obj.hLutChannelPopUp.string = sprintf('AI%d',mdfData.lutCalibrationChanID);
                    end
                end
            end
            
            function fieldName = chooseFieldName(varargin)
                fieldName = '';
                for i = 1:numel(varargin)
                    n = varargin{i};
                    if isfield(mdfData,n)
                        fieldName = n;
                        return;
                    end
                end
            end
            
            function propSet = setFromDifferentNames(propName,varargin)
                propSet = false;
                for i = 1:numel(varargin)
                    fieldName = varargin{i};
                    if isfield(mdfData,fieldName)
                        obj.(propName) = mdfData.(fieldName);
                        propSet = true;
                        return;
                    end
                end
            end
        end
        
        function s = getNewVarStruct(obj)
            if isempty(obj.heading)
                validName = matlab.lang.makeValidName(obj.scannerName);
                if isempty(obj.scannerName) || ismember(validName,obj.hConfigEditor.scannerNames)
                    s = [];
                    errordlg('Please give the scanner a unique name.','New Scanner');
                    return;
                end
                obj.scannerName = validName;
            end
            
            obj.etName.Enable = 'inactive';
            obj.etName.hCtl.BackgroundColor = .95*ones(1,3);
            set(obj.nameStuff, 'Visible', 'on');
            
            obj.listLabel = ['Scanner Settings (' obj.scannerName ')'];
            obj.descriptionText = ['Configure DAQ and scanning properties for the ''' obj.scannerName ''' scanning system. '...
                'Give the scanner a unique name and specify the scanner type. Previously configured beam DAQs and shutters can be assigned to this scanner.'];
            
            if obj.scannerTypeSel == 4
                s2dType = 'SlmScan';
                s.z__modelClass = 'scanimage.components.scan2d.SlmScan';
            elseif dabs.vidrio.rdi.Device.isRdiDeviceName(obj.acqDevId)
                s2dType = 'RggScan';
                s.z__modelClass = 'scanimage.components.scan2d.RggScan';
            elseif obj.scannerTypeSel == 3
                s2dType = 'LinScan';
                s.z__modelClass = 'scanimage.components.scan2d.LinScan';
            else
                s2dType = 'ResScan';
                s.z__modelClass = 'scanimage.components.scan2d.ResScan';
            end
            
            obj.heading = sprintf('%s (%s)', s2dType, obj.scannerName);
            
            
            rio = strsplit(obj.acqDev,' (');
            acquisitionDevName = rio{1};
            if (numel(rio) > 1) && isempty(strfind(rio{2},'not found'))
                fpgaDig = strsplit(strrep(rio{2},')',''),',');
                fpgaModuleType = fpgaDig{1};
                if numel(fpgaDig) > 1
                    fpgaDig{2} = strtrim(fpgaDig{2});
                    fpgaDig{2} = regexpi(fpgaDig{2},'^[^()-]+','match','once');
                    
                    digitizerModuleType = fpgaDig{2};
                else
                    if strncmp(fpgaModuleType,'NI5171',6)
                        fpgaModuleType = 'NI5171';
                    end
                    digitizerModuleType = '';
                end
            else
                fpgaModuleType = 'NI7961';
                digitizerModuleType = 'NI5732';
            end
            
            
            tableDat = obj.hShutterTable.Data;
            if ~isempty(tableDat)
                s.shutterIDs = find([tableDat{:,1}]);
            end
            if isempty(tableDat) || isempty(s.shutterIDs)
                s.shutterIDs = [];
            end
            
            s.channelsInvert = [obj.hChannelTable.Data{:,2}];
            s.customSigCondOption = obj.hCutomSignalCondPopup.string;
            if strcmp(s.customSigCondOption, 'None')
                s.customSigCondOption = '';
            end
            
            if obj.scannerTypeSel == 1
                s.scanheadModel = 'rmr';
            else
                s.scanheadModel = '';
            end
            
            if ismember(s2dType, {'LinScan' 'SlmScan'})
                s.deviceNameAcq = acquisitionDevName;
                s.deviceNameAux = obj.digIoDev;
                
                if ~obj.aisFixed
                    s.channelIDs = str2double(strrep(obj.hChannelTable.Data(:,1),'AI',''))';
                else
                    s.channelIDs = [];
                end
            elseif strcmp(s2dType, 'ResScan')
                s.rioDeviceID = acquisitionDevName;
                s.digitalIODeviceName = obj.digIoDev;
            else
                s.acquisitionDeviceId = acquisitionDevName;
            end
            
            if ismember(s2dType, {'ResScan' 'LinScan' 'SlmScan'})
                tableDat = obj.hBeamTable.Data;
                if ~isempty(tableDat)
                    bid = find([tableDat{:,1}],1);
                end
                if isempty(tableDat) || isempty(bid)
                    s.beamDaqID = [];
                else
                    s.beamDaqID = obj.hConfigEditor.beams{bid,2};
                end
                
                s.fpgaModuleType = fpgaModuleType;
                s.digitizerModuleType = digitizerModuleType;
            end
             
            if ismember(s2dType, {'RggScan' 'SlmScan'})
                if strcmp(s2dType, 'RggScan')
                    dev = s.acquisitionDeviceId;
                else
                    dev = s.deviceNameAcq;
                end
                tableDat = obj.hBeamTable.Data;
                if ~isempty(tableDat) && dabs.vidrio.rdi.Device.isRdiDeviceName(dev)
                    s.beamIds = find([tableDat{:,1}]);
                else
                    s.beamIds = [];
                end
            end
            
            if ismember(s2dType, {'ResScan' 'LinScan' 'RggScan'})
                s.externalSampleClock = logical(obj.useExtClk);
                s.externalSampleClockRate = str2double(obj.hExternalSampleClockRateEdit.String);
                if isnan(s.externalSampleClockRate)
                    s.externalSampleClockRate = [];
                end
                
                s.enableRefClkOutput = logical(obj.exprtClk);
                s.LaserTriggerPort = obj.hLaserPortPop.string;
            else
                if ~isempty(obj.slmTpye)
                    s.slmType = obj.hConfigEditor.slmName2RegMap(obj.slmTpye);
                else
                    s.slmType = 'simulated';
                end
                s.focalLength = obj.focalLength;
                s.slmMediumRefractiveIdx = obj.slmMediumRefractiveIdx;
                s.objectiveMediumRefractiveIdx = obj.objectiveMediumRefractiveIdx;
                s.zeroOrderBlockRadius = obj.zeroOrderBlockRadius;
                
                s.linearScannerName = obj.slmLinScanner;
                if strcmp(s.linearScannerName, 'None')
                    s.linearScannerName = '';
                end
                
                s.lutCalibrationDaqDevice = obj.lutDev;
                str = obj.hLutChannelPopUp.string;
                if isempty(obj.lutDev) || isempty(str) || strcmp(str,'None')
                    s.lutCalibrationChanID = [];
                else
                    s.lutCalibrationChanID = str2double(str(3:end));
                end
            end
            
            if ismember(s2dType, {'ResScan' 'RggScan'})
                s.externalSampleClock = logical(obj.useExtClk);
                s.externalSampleClockRate = str2double(obj.hExternalSampleClockRateEdit.String);
                if isnan(s.externalSampleClockRate)
                    s.externalSampleClockRate = [];
                end
                
                s.extendedRggFov = obj.extendedFov;
                
                s.enableRefClkOutput = logical(obj.exprtClk);
                s.nominalResScanFreq = str2double(obj.hNominalFrequencyEdit.String);
                
                if obj.scannerTypeSel == 1
                    if s.nominalResScanFreq > 11e3
                        s.resonantAngularRange = 12;
                    else
                        s.resonantAngularRange = 26;
                    end
                    s.rScanVoltsPerOpticalDegree = 5/s.resonantAngularRange;
                elseif obj.scannerTypeSel == 2
                    s.resonantAngularRange = obj.resAngularRange;
                    v = str2num(obj.hResMaxVoltageCmdEdit.String) / s.resonantAngularRange;
                    s.rScanVoltsPerOpticalDegree = round(v*10000)/10000;
                else
                    s.resonantAngularRange = [];
                end
                s.resonantScannerSettleTime = str2double(obj.hResSettlingTimeEdit.String);
                s.resonantZoomDeviceName = obj.zoomCtlDaq;
                s.resonantEnableTerminal = strtrim(obj.hResEnableTerminalPopUp.string);
                
                if obj.acqDevIsRdi
                    s.resonantSyncInputTerminal = strtrim(obj.hResSyncTermPopUp.string);
                end
                
                str = obj.hResZoomChannelIDPopUp.string;
                val = regexpi(str,'AO([0-9]+)','tokens');
                if ~isempty(val)
                    val = str2double(val{1}{1});
                else
                    val = strtrim(str);
                end
                s.resonantZoomAOChanID = val;
                
                s.galvoDeviceName = obj.galvoDaq;
                
                if obj.hasXGalvo
                    s.galvoAOChanIDX = str2double(obj.xGalvoChanSel(3:end));
                else
                    s.galvoAOChanIDX = [];
                end
                
                s.galvoAOChanIDY = str2double(obj.hYGalvoAnalogOutputChannelIDPopUp.string(3:end));
                
                if obj.scannerTypeSel == 1
                    s.galvoParkDegreesX = -10;
                    s.galvoVoltsPerOpticalDegreeX = 1;
                    s.xGalvoAngularRange = 20;
                    s.galvoParkDegreesY = -10;
                    s.galvoVoltsPerOpticalDegreeY = 1;
                    s.yGalvoAngularRange = 20;
                else
                    s.galvoParkDegreesX = str2double(obj.hXGalvoParkAngleEdit.String);
                    s.galvoVoltsPerOpticalDegreeX = str2num(obj.hXGalvoOpticalConversionFactorEdit.String);
                    s.xGalvoAngularRange = obj.xgalvoAngularRange;
                    s.galvoParkDegreesY = str2double(obj.hYGalvoParkAngleEdit.String);
                    s.galvoVoltsPerOpticalDegreeY = str2num(obj.hYGalvoOpticalConversionFactorEdit.String);
                    s.yGalvoAngularRange = str2num(obj.hYGalvoMaxAngularRangeEdit.String);
                end
                
                s.galvoAIChanIDX = chanIdAndTermCfg(obj.hXGalvoInputChannelIDPopUp.string);
                s.galvoAIChanIDY = chanIdAndTermCfg(obj.hYGalvoInputChannelIDPopUp.string);
                
            elseif strcmp(s2dType, 'LinScan')
                s.deviceNameGalvo = obj.galvoDaq;
                s.deviceNameGalvoFeedback = obj.galvoFeedbackDaq;
                s.deviceNameOffset = obj.galvoOffsetDaq;
                
                s.XMirrorChannelID = str2double(obj.xGalvoChanSel(3:end));
                s.scanParkAngleX = str2double(obj.hXGalvoParkAngleEdit.String);
                s.voltsPerOpticalDegreeX = str2num(obj.hXGalvoOpticalConversionFactorEdit.String);
                s.xGalvoAngularRange = obj.xgalvoAngularRange;
                
                s.YMirrorChannelID = str2double(obj.hYGalvoAnalogOutputChannelIDPopUp.string(3:end));
                s.scanParkAngleY = str2double(obj.hYGalvoParkAngleEdit.String);
                s.voltsPerOpticalDegreeY = str2num(obj.hYGalvoOpticalConversionFactorEdit.String);
                s.yGalvoAngularRange = str2num(obj.hYGalvoMaxAngularRangeEdit.String);
                
                [s.XMirrorPosChannelID, s.XMirrorPosTermCfg] = chanIdAndTermCfg(obj.hXGalvoInputChannelIDPopUp.string);
                [s.YMirrorPosChannelID, s.YMirrorPosTermCfg] = chanIdAndTermCfg(obj.hYGalvoInputChannelIDPopUp.string);
                
                s.XMirrorOffsetChannelID = chanFromStr(obj.hXGalvoAnalogOutputOffsetPopUp.string);
                s.YMirrorOffsetChannelID = chanFromStr(obj.hYGalvoAnalogOutputOffsetPopUp.string);
            end
        end
        
        function [lvl,v,errMsg] = validateDaqChoice(obj,v,oldV)
            errMsg = '';
%             allowChange = isvarname(v);
            lvl = 2 * ~ismember(v,obj.hDigitalIODevicePopUp.choices);
            if lvl > 0
                errMsg = 'Error: must be an X series DAQ in the same PXI chassis as the FPGA/digitizer';
            end
%             if ~allowChange
%                 v = oldV;
%             end
        end
        
        function [lvl,v,errMsg] = validateZoomDaqChoice(obj,v,oldV)
            errMsg = '';
%             allowChange = isvarname(v);
            lvl = 2 * ~ismember(v,obj.hResZoomDevicePopUp.choices);
            if lvl > 0
                errMsg = 'Error: must be a valid DAQ name';
            end
%             if ~allowChange
%                 v = oldV;
%             end
        end
        
        function beamCellEditFcn(obj,~,evt)
            beams = obj.hConfigEditor.beams;
            daqId = beams{evt.Indices(1),2};
            
            % if i just enabled a beam, disable beams on all other daqs
            if evt.NewData
                inds = [beams{:,2}] ~= daqId;
                obj.hBeamTable.Data(inds,1) = {false};
            end
            
            % is this is not using vdaq, all beams on a given daq must have
            % same setting
            if ~obj.acqDevIsRdi
                inds = [beams{:,2}] == daqId;
                obj.hBeamTable.Data(inds,1) = {evt.NewData};
            end
        end
        
        function showAdvanced(obj,varargin)
            obj.hAdvButtonPanel.Visible = 'off';
            set(obj.advancedStuff,'visible', 'on');
            
            obj.updatePanelSize();
        end
        
        function extendedFovModeSet(obj,varargin)
            obj.defaultExtendedFov = false;
        end
        
        function updatePanelSize(obj)
            showDaqOptions = strcmp(obj.vdaqHideSections(1).Visible,'on');
            showResOptions = strcmp(obj.hResSection.Visible,'on');
            showGalvOptions = strcmp(obj.hGalvoSection.Visible,'on');
            showRmrOptions = strcmp(obj.nonRmrStuff(1).Visible,'on');
            showSlmOptions = strcmp(obj.slmStuff(1).Visible,'on');
            showAdvOptions = strcmp(obj.advancedStuff(1).Visible,'on');
            showOffOptions = strcmp(obj.offsetStuff(1).Visible,'on');
            showExtendedOptions = strcmp(obj.extendedStuff.Visible,'on');
            
            baseH = 360 + 46*showDaqOptions;
            
            resH = 346 + 44*showDaqOptions - 90*~showRmrOptions;
            set(obj.hResSection, 'HeightLimits', resH * ones(1,2));
            set(obj.hResPanel, 'HeightLimits',(resH - 30)*ones(1,2));
            
            
            yGalvoInnerPnlH = 274 + 90*showOffOptions - 140*~showRmrOptions;
            xGalvoInnerPnlH = yGalvoInnerPnlH + 50*showExtendedOptions;
            galvoPnlH = max(xGalvoInnerPnlH,yGalvoInnerPnlH) + 65 + 70*showDaqOptions;
            galvoSectionH = galvoPnlH+30;
            set(obj.hXGalvoPanel, 'HeightLimits', xGalvoInnerPnlH * ones(1,2));
            set(obj.hYGalvoPanel, 'HeightLimits', yGalvoInnerPnlH * ones(1,2));
            set(obj.hGalvoPanel, 'HeightLimits',galvoPnlH*ones(1,2));
            set(obj.hGalvoSection, 'HeightLimits',galvoSectionH*ones(1,2));
            
            slmSectionH = 460;
            advancedSectionH = 170;
            
            obj.hPanel.Units = 'pixels';
            obj.hPanel.Position(4) = baseH + resH*showResOptions + galvoSectionH*showGalvOptions + slmSectionH*showSlmOptions + advancedSectionH*showAdvOptions;
            obj.hConfigEditor.resizePnl();
        end
        
        function applyDefaultExtendedFov(obj)
            if obj.defaultExtendedFov
                obj.extendedFov = obj.xgalvoAngularRange > obj.resAngularRange;
            end
        end
    end
    
    %% prop access
    methods
        function set.acqDev(obj, v)
            dev = strsplit(v,' ');
            dev = dev{1};
            obj.acqDevId = dev;
            if isfield(obj.hConfigEditor.rioInfo, dev)
                obj.numChans = obj.hConfigEditor.rioInfo.(dev).numAcqChans;
                obj.hChannelTable.ColumnEditable = [false true];
                obj.hChannelTable.ColumnFormat = {'char' 'logical'};
                obj.aisFixed = true;
            elseif ismember(dev,obj.hConfigEditor.availableDaqs)
                [~,idx] = ismember(dev,obj.hConfigEditor.availableDaqs);
                if obj.hConfigEditor.daqInfo(idx).simultaneousSampling
                    obj.numChans = min(4,obj.hConfigEditor.daqInfo(idx).numAIs);
                else
                    obj.numChans = 1;
                end
                
                numAvailChans = obj.hConfigEditor.daqInfo(idx).numAIs;
                obj.hChannelTable.ColumnEditable = [true true];
                obj.hChannelTable.ColumnFormat = {arrayfun(@(x){sprintf('  AI%d',x)},0:(numAvailChans-1)) 'logical'};
                obj.aisFixed = false;
            else
                obj.numChans = 1;
                obj.hChannelTable.ColumnEditable = [false true];
                obj.hChannelTable.ColumnFormat = {'char' 'logical'};
                obj.aisFixed = true;
            end
            
            % make sure it is a selection from the list
            chcs = obj.pmAcqDaq.choices;
            idx = find(strncmp(dev, chcs, length(dev)),1);
            if isempty(v) || isempty(idx)
                obj.acqDev = v;
            else
                obj.acqDev = chcs{idx};
            end
            
            % set list of valid daqs for the other drop downs
            obj.acqDevIsRdi = dabs.vidrio.rdi.Device.isRdiDeviceName(dev);
            if obj.acqDevIsRdi
                obj.digIoDev = dev;
                obj.zoomCtlDaq = dev;
                obj.galvoDaq = dev;
                obj.galvoFeedbackDaq = dev;
            else
                if obj.scannerTypeSel < 3
                    if isfield(obj.hConfigEditor.rioInfo,dev)
                        pxiNum = obj.hConfigEditor.rioInfo.(dev).pxiNumber;
                        daqChoices = obj.hConfigEditor.availableDaqs(([obj.hConfigEditor.daqInfo.pxiNum] == pxiNum) & [obj.hConfigEditor.daqInfo.isXSer]);
                        obj.hDigitalIODevicePopUp.choices = daqChoices;
                        obj.hGalvoCtlDaqPopUp.choices = daqChoices;
                    else
                        obj.hDigitalIODevicePopUp.choices = {};
                        obj.hGalvoCtlDaqPopUp.choices = {};
                    end
                elseif strcmp(obj.scannerType, 'linear')
                    if isfield(obj.hConfigEditor.rioInfo,dev)
                        pxiNum = obj.hConfigEditor.rioInfo.(dev).pxiNumber;
                        daqChoices = obj.hConfigEditor.availableDaqs(([obj.hConfigEditor.daqInfo.pxiNum] == pxiNum) & [obj.hConfigEditor.daqInfo.isXSer]);
                        obj.hDigitalIODevicePopUp.choices = daqChoices;
                        obj.hGalvoCtlDaqPopUp.choices = daqChoices;
                    else
                        obj.hDigitalIODevicePopUp.choices = obj.hConfigEditor.availableDaqs([obj.hConfigEditor.daqInfo.isXSer]);
                        obj.hGalvoCtlDaqPopUp.choices = obj.hConfigEditor.availableDaqs;
                    end
                else
                    obj.hDigitalIODevicePopUp.choices = obj.hConfigEditor.availableDaqs([obj.hConfigEditor.daqInfo.isXSer]);
                end
            end
            
            [fpga,adaptermodule] = getFpgaAndModuleFromAcqDev(obj.acqDev);
            mask = regexpi(obj.hConfigEditor.availableBitfiles,['^Microscopy\s*' fpga '\s*((-[0-9]+)|(' adaptermodule '))']);
            mask = cellfun(@(m)~isempty(m),mask);
            
            if any(mask)
                ops = regexpi(obj.hConfigEditor.availableBitfiles(mask),'.*\((.*)\)','tokens');
                ops = [ops{:}];
                ops = [ops{:}];
                
                obj.hCutomSignalCondPopup.choices = [{'None'} ops];
                obj.hCutomSignalCondPopup.string = obj.hCutomSignalCondPopup.choices{1};
            else
                obj.hCutomSignalCondPopup.choices = {'None'};
                obj.hCutomSignalCondPopup.string = 'None';
            end
            
            obj.updateLaserPortChoices();
            obj.updatePanelSize();
            
            function [fpga,adaptermodule] = getFpgaAndModuleFromAcqDev(acqDev)
                fpga = '';
                adaptermodule = '';
                
                tokens = regexp(acqDev,'[^\(]+\(\s*([^,\s\(\)]*)\s*,?\s*([^()-\s]*)','tokens');
                if ~isempty(tokens) && ~isempty(tokens{1})
                    fpga = tokens{1}{1};
                    
                    if ~isempty(regexpi(fpga,'NI5171'))
                        fpga = 'NI5171';
                    end
                end
                
                if ~isempty(tokens) && ~isempty(tokens{1}) && numel(tokens{1})>=2
                    adaptermodule = tokens{1}{2};
                end
            end
        end
        
        function set.acqDevIsRdi(obj,v)
            obj.acqDevIsRdi = v;
            set(obj.vdaqHideSections,'Visible',obj.tfMap(~v));
            set(obj.vdaqShowSections,'Visible',obj.tfMap(v));
            set(obj.offsetStuff,'Visible',obj.tfMap(~v));
        end
        
        function set.numChans(obj, v)
            obj.numChans = v;
            
            dat = obj.hChannelTable.Data;
            dat(end+1:obj.numChans,2) = {false};
            dat(obj.numChans+1:end,:) = [];
            dat(:,1) = arrayfun(@(x)sprintf('  AI%d',x),0:obj.numChans-1,'uniformoutput',false);
            obj.hChannelTable.RowName = arrayfun(@(x)sprintf('CH%d',x),1:obj.numChans,'uniformoutput',false);
            
            obj.hChannelTable.Data = dat;
        end
        
        
        function set.useExtClk(obj, v)
            obj.hExternalSampleClockRateEdit.Enable = obj.tfMap(v);
            obj.useExtClk = v;
        end
        
        function set.scannerType(obj,v)
            switch lower(v)
                case 'rmr'
                    obj.scannerTypeSel = 1;
                case 'resonant'
                    obj.scannerTypeSel = 2;
                case 'linear'
                    obj.scannerTypeSel = 3;
                case 'slm'
                    obj.scannerTypeSel = 4;
                otherwise
                    error('Invalid scanner type.');
            end
        end
        
        function v = get.scannerType(obj)
            types = {'rmr' 'resonant' 'linear' 'slm'};
            v = types{obj.scannerTypeSel};
        end
        
        function set.scannerTypeSel(obj, v)
            ov = obj.scannerTypeSel;
            if ~isempty(obj.heading) && ~obj.internalSet && (ov ~= v) && ((v > 2) || (ov > 2))
                if strcmp('Cancel',questdlg('This change in scanner type will reset associated alignment and calibration data. Continue?','Change Scanner Type','Continue','Cancel','Cancel'))
                    return
                end
            end
            
            if v>3
                msgbox('Selected Scanner is only available in ScanImage Premium.','Version Warning.','warn');
                return
            end
            
            obj.scannerTypeSel = v;
            
            set(obj.hResSection, 'Visible', obj.tfMap(v<3));
            set(obj.hGalvoSection, 'Visible', obj.tfMap(v<4));
            set(obj.nonRmrStuff, 'Visible', obj.tfMap(v>1));
            set(obj.slmStuff, 'Visible', obj.tfMap(v==4));
            set(obj.hAdvButtonPanel, 'Visible', obj.tfMap(v<4));
            set(obj.extendedStuff, 'Visible', obj.tfMap(v==2));
            set(obj.advancedStuff, 'Visible', 'off');
            
            if v < 3
                obj.acqDevChoices = obj.hConfigEditor.rioChoices;
                obj.galvoFeedbackDaq = obj.galvoDaq;
                obj.hGalvoFdbkDaqPopUp.enable = 'off';
                
                if v == 1
                    obj.hResMaxVoltageCmdEdit.String = 5;
                    obj.resAngularRange = 26;
                    
                    obj.xgalvoAngularRange = 20;
                    obj.hXGalvoOpticalConversionFactorEdit.String = 1;
                    obj.hXGalvoParkAngleEdit.String = -10;
                    
                    obj.hYGalvoMaxAngularRangeEdit.String = 20;
                    obj.hYGalvoOpticalConversionFactorEdit.String = 1;
                    obj.hYGalvoParkAngleEdit.String = -10;
                end
            else
                obj.acqDevChoices = [obj.hConfigEditor.rioChoices; obj.hConfigEditor.availableDaqs];
                obj.hGalvoFdbkDaqPopUp.enable = 'on';
            end
            obj.acqDev = obj.acqDev;
        end
        
        function v = get.canLinearScan(obj)
            v = (obj.scannerTypeSel == 3) || (obj.acqDevIsRdi && obj.hasXGalvo);
        end
        
        function v = get.canPhotostim(obj)
            v = (obj.scannerTypeSel > 2) || (obj.acqDevIsRdi && obj.hasXGalvo);
        end
        
        function set.zoomCtlDaq(obj, v)
            obj.zoomCtlDaq = v;
            
            [tf, idx] = ismember(v,obj.hConfigEditor.availableDaqs);
            if tf
                nfo = obj.hConfigEditor.daqInfo(idx);
                zoomControlOptions = [{' '} nfo.allAOs];
                
                if dabs.vidrio.rdi.Device.isRdiDeviceName(v)
                    enableOptions = [{' '}; nfo.olines(:)];
                else
                    enableOptions = [{' '} setdiff(nfo.pfi,'PFI0','stable')];
                end
                
                if dabs.vidrio.rdi.Device.isRdiDeviceName(v)
                    syncOptions = nfo.ilines(:);
                else
                    syncOptions = {' '};
                end
            else
                zoomControlOptions = {' '};
                enableOptions = {' '};
                syncOptions = {' '};
            end
            
            obj.hResZoomChannelIDPopUp.choices = zoomControlOptions;
            obj.hResEnableTerminalPopUp.choices = enableOptions;
            obj.hResSyncTermPopUp.choices = syncOptions;
        end
        
        function updateLaserPortChoices(obj)
            if obj.acqDevIsRdi
                obj.hLaserPortPop.choices = obj.hConfigEditor.rioInfo.(obj.acqDevId).allDs;
            elseif obj.scannerTypeSel < 3
                obj.hLaserPortPop.choices = {'' 'DIO0.0' 'DIO0.1' 'DIO0.2' 'DIO0.3'};
            else
                obj.hLaserPortPop.choices = [{'' 'DIO0.0' 'DIO0.1' 'DIO0.2' 'DIO0.3'} arrayfun(@(n){sprintf('PFI%d',n)},0:15)];
            end
        end
        
        function set.galvoDaq(obj, v)
            obj.galvoDaq = v;
            
            [tf, idx] = ismember(v,obj.hConfigEditor.availableDaqs);
            if tf
                aos = obj.hConfigEditor.daqInfo(idx).allAOs;
            else
                aos = {'AO0' 'AO1'};
            end
            
            obj.hXGalvoAnalogOutputChannelIDPopUp.choices = [{'None'} aos];
            obj.hYGalvoAnalogOutputChannelIDPopUp.choices = aos;
            
            if obj.scannerTypeSel < 3
                obj.galvoFeedbackDaq = v;
            end
        end
        
        function set.galvoFeedbackDaq(obj, v)
            obj.galvoFeedbackDaq = v;
            
            [tf, idx] = ismember(v,obj.hConfigEditor.availableDaqs);
            if tf
                ais = obj.hConfigEditor.daqInfo(idx).allAIs;
                if strcmp(obj.hConfigEditor.daqInfo(idx).productCategory, 'DAQmx_Val_XSeriesDAQ')
                    ais = [ais strcat(ais, ' RSE')];
                end
            else
                ais = {};
            end
            obj.hXGalvoInputChannelIDPopUp.choices = [{''} ais];
            obj.hYGalvoInputChannelIDPopUp.choices = [{''} ais];
        end
        
        function set.lutDev(obj, v)
            obj.lutDev = v;
            
            [tf, idx] = ismember(v,obj.hConfigEditor.availableDaqs);
            if tf
                obj.hLutChannelPopUp.choices = obj.hConfigEditor.daqInfo(idx).allAIs;
            else
                obj.hLutChannelPopUp.choices = {};
            end
        end
        
        function set.galvoOffsetDaq(obj, v)
            obj.galvoOffsetDaq = v;
            
            hasv = ~isempty(v);
            if hasv
                [tf, idx] = ismember(v,obj.hConfigEditor.availableDaqs);
                if tf
                    aos = obj.hConfigEditor.daqInfo(idx).allAOs;
                else
                    aos = {'AO0' 'AO1'};
                end
                
                obj.hXGalvoAnalogOutputOffsetPopUp.choices = [{''} aos];
                obj.hYGalvoAnalogOutputOffsetPopUp.choices = [{''} aos];
            end
            
            enX = obj.tfMap(obj.hasXGalvo && hasv);
            obj.hXGalvoAnalogOutputOffsetPopUp.enable = enX;
            obj.hXGalvoMaximumVoltageOutputEdit.Enable = enX;
            
            enY = obj.tfMap(hasv);
            obj.hYGalvoAnalogOutputOffsetPopUp.enable = enY;
            obj.hYGalvoMaximumVoltageOutputEdit.Enable = enY;
        end
        
        function set.xGalvoChanSel(obj,v)
            if isempty(v)
                v = 'None';
            end
            obj.xGalvoChanSel = v;
            obj.hasXGalvo = ~strcmp(v,'None');
        end
        
        function set.hasXGalvo(obj,v)
            obj.hasXGalvo = v;
            
            en = obj.tfMap(v);
            obj.hXGalvoMaxAngularRangeEdit.Enable = en;
            obj.hXGalvoOpticalConversionFactorEdit.Enable = en;
            obj.hXGalvoParkAngleEdit.Enable = en;
            obj.hXGalvoInputChannelIDPopUp.enable = en;
            obj.hXGalvoExtendedFov.Enable = en;
            
            enX = obj.tfMap(v && ~isempty(obj.galvoOffsetDaq));
            obj.hXGalvoAnalogOutputOffsetPopUp.enable = enX;
            obj.hXGalvoMaximumVoltageOutputEdit.Enable = enX;
        end
        
        function set.defaultExtendedFov(obj,v)
            obj.defaultExtendedFov = v;
            
            if v
                obj.hXGalvoExtendedFov.String = 'Extended Resonant FOV (default)';
            else
                obj.hXGalvoExtendedFov.String = 'Extended Resonant FOV';
            end
            
            obj.applyDefaultExtendedFov();
        end
        
        function set.resAngularRange(obj,v)
            obj.resAngularRange = v;
            obj.applyDefaultExtendedFov();
        end
        
        function set.xgalvoAngularRange(obj,v)
            obj.xgalvoAngularRange = v;
            obj.applyDefaultExtendedFov();
        end
    end
end

function ch = chanFromStr(str)
    if isempty(str)
        ch = [];
    else
        ch = str2double(str(3:end));
    end
end

function [ch, cfg] = chanIdAndTermCfg(str)
    ch = strsplit(str,' ');
    if numel(ch) > 1
        cfg = ch{2};
    else
        cfg = 'Differential';
    end
    ch = ch{1};
    ch = str2double(ch(3:end));
    if isnan(ch)
        ch = [];
    end
end



%--------------------------------------------------------------------------%
% ScannerPage.m                                                            %
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
