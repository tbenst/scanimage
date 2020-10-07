classdef ConfigurationEditor < most.Gui
    
    properties
        hMdfSectionPanel;
        hActivePage;
        
        initDone = false;
        
        % known sections that must be there
        hAllPages = [];
        hSIPage = {};
        hShuttersPage = {};
        hBeamsPage = {};
        hScannerPages = scanimage.guis.configuration.ScannerPage.empty;
        hMotorsPage = {};
        hFastZPage = {};
        hPhotostimPage = {};
        hIntegrationRoiOutputsPage = {};
        hThorLabsBScope2Page = {};
        hThorLabsECUScannersPage = {};
        hPMTControllersPage = {};
        hLegacyMotorsPage = {};
        hLSCPureAnalogPage = {};
        hOtherPages = {};
        
        
        hSecPanel
        hRawTable;
        hButtonFlow;
        hButtons = [];
        hTitleSt;
        hDescSt;
        hAdditionalComponentsPanel;
        
        hMDF;
        mdfHdgs;
        
        daqInfo = scanimage.guis.configuration.DaqInfo.empty(1,0);
        allDigChans = {};
        allInputDigChans;
        allOutputDigChans;
        
        availableRios
        rioInfo;
        simRioAdded;
        
        hSlmRegistry;
        slmName2RegMap;
        
        hMotorRegistry;
        motorName2RegMap;
        
        hMotorRegistryNew;
        
        buttonsWidth = 260;
        
        isWizardMode = false;
        wizardDone = false;
        wizardAddedMotors;
        wizardAddedMotorHeadings;
        wizardAddedFastZ;
        wizardAddedPhotostim;
        wizardAddedIntegration;
        contHit = false;
        pageSeenBefore;
        
        hNewScanner;
        
        rawView = false;
        
        scannerMap;
        s2dNames;
    end
    
    properties (SetObservable)
        rioChoices;
        availableBitfiles;
        availableDaqs;
        availableComPorts;
        fastZMotors;
    end
    
    properties (Dependent)
        scannerNames;
        scannerCanLinearScan;
        scannerCanPhotostim;
        scannerIsResonant;
        
        numShutters;
        shutterNames;
        numBeamDaqs;
        beamDaqNames;
        beams;
        simulated;
        selectedPage;
    end
    
    properties (Hidden, Constant)
        ADAPTER_MODULE_CHANNEL_COUNT = containers.Map({'NI5732','NI5733','NI5734','NI5751','NI517x','NI5771'},{2,2,4,4,4,4});
    end
    
    events
        mdfUpdate;
    end
    
    %% Lifecycle
    methods
        function obj = ConfigurationEditor(mdfPath,initNow,persist)
            if ~nargin
                mdfPath = [];
            end
            
            if nargin < 2 || isempty(initNow)
                initNow = true;
            end
            
            if nargin < 3 || isempty(persist)
                persist = false;
            end
            
            obj = obj@most.Gui([], [], [250 60], 'characters');
            set(obj.hFig,'Name','ScanImage Machine Configuration Editor','Resize','on');
            
            if persist
                set(obj.hFig,'CloseRequestFcn',@(varargin)obj.set('Visible',false));
            end
            
            if initNow
                obj.init(mdfPath);
                if most.idioms.isValidObj(obj)
                    obj.selectedPage = 1;
                    obj.Visible = true;
                end
            end
        end
        
        function justInit = init(obj,mdfPath)
            h = msgbox('Loading configuration editor...');
            delete(h.Children(1));
            h.Children.Position = [0 -.15 1 .5];
            drawnow();
            
            try
                if nargin > 1 && ~isempty(mdfPath)
                    obj.hMDF = most.MachineDataFile.getInstance();
                    obj.hMDF.load(mdfPath);
                end
                
                justInit = ~obj.initDone;
                if justInit
                    
                    obj.hMDF = most.MachineDataFile.getInstance();
                    if ~obj.hMDF.isLoaded
                        [mdffile, mdfpath] = uigetfile('*.m','Select machine data file...');
                        if length(mdffile) > 1
                            obj.hMDF.load([mdfpath mdffile]);
                        else
                            delete(h);
                            delete(obj);
                            return;
                        end
                    end
                    
                    %enumerate scan2d types
                    s2dp = 'scanimage/components/scan2d';
                    list = what(s2dp);
                    list = list(1); % workaround for sparsely occuring issue where list is a 2x1 structure array, where the second element is empty
                    s2dp = [strrep(s2dp,'/','.') '.'];
                    names = cellfun(@(x)[s2dp x(1:end-2)],list.m,'UniformOutput',false);
                    obj.s2dNames = cellfun(@(x){eval(strcat(x,'.mdfHeading'))},names);
                    
                    obj.migrateSettings();
                    
                    mainContainer = most.gui.uiflowcontainer('Parent',obj.hFig,'FlowDirection','TopDown','Units','norm','Position',[0 0 1 1]);
                    topContainer = most.gui.uiflowcontainer('Parent',mainContainer,'FlowDirection','LeftToRight');
                    
                    obj.hButtonFlow = most.gui.uiflowcontainer('Parent',topContainer,'FlowDirection','TopDown','margin',0.00001,'WidthLimits',obj.buttonsWidth);
                    
                    bottomContainer = most.gui.uiflowcontainer('Parent',mainContainer,'FlowDirection','LeftToRight','margin',0.00001, 'HeightLimits', 32);
                    bottomLeftContainer = most.gui.uiflowcontainer('Parent',bottomContainer,'FlowDirection','LeftToRight');
                    obj.addUiControl('Parent',bottomLeftContainer,'string','Add New Scanner','tag','pbAdd','callback',@obj.newScanner,'WidthLimits',obj.buttonsWidth);
                    obj.addUiControl('Parent',bottomLeftContainer,'string','Remove This Scanner','tag','pbDelete','callback',@obj.deleteScanner, 'WidthLimits', 200);
                    
                    buttonContainer = most.gui.uiflowcontainer('Parent',bottomContainer,'FlowDirection','RightToLeft');
                    obj.addUiControl('Parent',buttonContainer,'string','Cancel','tag','pbCancel','callback',@(varargin)set(obj,'Visible',false));
                    obj.addUiControl('Parent',buttonContainer,'string','Revert','tag','pbRevert','callback',@obj.pbRevertCb);
                    obj.addUiControl('Parent',buttonContainer,'string','Apply','tag','pbApply','callback',@obj.pbApplyCb);
                    obj.addUiControl('Parent',buttonContainer,'string','OK','tag','pbOk','callback',@obj.pbOkCb);
                    set([obj.pbCancel obj.pbRevert obj.pbApply obj.pbOk], 'WidthLimits', 100*ones(1,2));
                    
                    obj.hSecPanel = uipanel('Parent', topContainer);
                    secContainer = most.gui.uiflowcontainer('Parent',obj.hSecPanel,'FlowDirection','TopDown','margin',0.00001);
                    
                    titlePanel = uipanel('Parent', secContainer,'BorderType', 'none');
                    set(titlePanel, 'HeightLimits', 96*ones(1,2));
                    obj.hTitleSt = uicontrol('parent', titlePanel, 'style', 'text','units','pixels','position',[46 56 500 30],'FontSize',14,'horizontalalignment','left');
                    obj.hDescSt = uicontrol('parent', titlePanel, 'style', 'text','units','pixels','position',[46 10 750 48],'FontSize',10,'horizontalalignment','left');
                    annotation(titlePanel,'line',[.02 .98],.01*ones(1,2), 'LineWidth', 1);
                    
                    secScrlContainer = most.gui.uiflowcontainer('Parent',secContainer,'FlowDirection','RightToLeft');
                    obj.addUiControl('Parent',secScrlContainer,'Style','slider','tag', 'slSecScroll','LiveUpdate',true,'callback',@obj.srcllCb);
                    set(obj.slSecScroll.hCtl, 'WidthLimits', [18 18]);
                    obj.hMdfSectionPanel = uipanel('Parent', secScrlContainer,'BorderType', 'none','SizeChangedFcn',@obj.resizePnl);
                    
                    obj.hRawTable = uitable('Parent', topContainer,...
                        'Data', {false '' '' ''}, ...
                        'ColumnName', {'Delete' 'Variable Name' 'Value' 'Comment'}, ...
                        'ColumnFormat', {'logical' 'char' 'char' 'char'}, ...
                        'ColumnEditable', [true true true true], ...
                        'ColumnWidth', {50 200 200 700}, ...
                        'RowName', [], ...
                        'RowStriping', 'Off', ...
                        'Visible', 'Off', ...
                        'CellEditCallback', @obj.rawTableCellEditFcn);
                    
                    obj.hFig.WindowScrollWheelFcn = @obj.scrollWheelFcn;
                    obj.hFig.WindowKeyPressFcn = @obj.keyPressFcn;
                    
                    obj.scannerMap = containers.Map;
                    obj.initDone = true;
                    
                    obj.initDaqInfo();
                    obj.initMotorSlmInfo();
                    obj.refreshPages();
                    obj.reportDaqUsage();
                    
                    if obj.simulated
                        % refresh again to add simulated RIO device
                        obj.addSimRio();
                    end
                else
                    obj.deleteAllPages();
                    obj.migrateSettings();
                    obj.initDaqInfo();
                    obj.initMotorSlmInfo();
                    obj.refreshPages();
                end
                
                delete(h);
            catch ME
                delete(h);
                warndlg('Failed to launch Configuration Editor. See command window for details.','ScanImage');
                ME.rethrow();
            end
        end
        
        function constructAddlCompsPnl(obj)
            if ~most.idioms.isValidObj(obj.hAdditionalComponentsPanel)
                ph = 525;
                obj.hAdditionalComponentsPanel = uipanel('parent',[],'BorderType','none','units','pixels','position',[0 0 400 ph]);
                
                args = {'parent', obj.hAdditionalComponentsPanel, 'units','pixels','fontsize',10};
                uicontrol(args{:},'string', 'Add Another Scanner','position',[46 ph-76 300 50],'callback',@(varargin)obj.newScanner);
                uicontrol(args{:},'string', 'Add Stage Controller(s)','position',[46 ph-136 300 50],'callback',@(varargin)addComp('wizardAddedMotors','Motors'));
                uicontrol(args{:},'string', 'Add FastZ Actuator','position',[46 ph-196 300 50],'callback',@(varargin)addComp('wizardAddedFastZ','FastZ'));
                b3 = uicontrol(args{:},'string', 'Add Cameras','position',[46 ph-256 300 50],'callback',@(varargin)addComp('wizardAddedCameras','CameraManager'));
                b1 = uicontrol(args{:},'string', 'Configure Photostimulation','position',[46 ph-316 300 50],'callback',@(varargin)addComp('wizardAddedPhotostim','Photostim'));
                b2 = uicontrol(args{:},'string', 'Configure Closed Loop Experiment Outputs','position',[46 ph-376 300 50],'callback',@(varargin)addComp('wizardAddedIntegration','IntegrationRoiOutputs'));
                uicontrol(args{:},'string', 'Finish and Run ScanImage','position',[46 ph-436 300 50],'callback',@obj.pbApplyCb);
                set([b1 b2 b3], 'enable', 'off');
            end
            
            function addComp(nm,hdg)
                obj.(nm) = true;
                obj.refreshPages();
                obj.selectedPage = hdg;
            end
        end
        
        function delete(obj)
            most.idioms.safeDeleteObj(obj.hFig);
            arrayfun(@delete,obj.hAllPages);
            most.idioms.safeDeleteObj(obj.scannerMap);
        end
    end
    
    methods
        function resizePnl(obj,varargin)
            if isa(obj.hActivePage, 'matlab.ui.container.Panel')
                obj.slSecScroll.hCtl.Visible = 'off';
                obj.hMdfSectionPanel.Units = 'pixels';
                cSz = obj.hMdfSectionPanel.Position;
                
                obj.hActivePage.Units = 'pixels';
                pSz = obj.hActivePage.Position;
                pSz(2) = cSz(4) - pSz(4);
                obj.hActivePage.Position = pSz;
            elseif ~isempty(obj.hActivePage) && most.idioms.isValidObj(obj.hActivePage)
                obj.hMdfSectionPanel.Units = 'pixels';
                cSz = obj.hMdfSectionPanel.Position;
                obj.hActivePage.resizePnl(cSz(3));
                
                ph = obj.hActivePage.hPanel.Position(4);
                
                if ph > cSz(4)
                    obj.slSecScroll.hCtl.Visible = 'on';
                    pv = obj.slSecScroll.hCtl.Max - obj.slSecScroll.hCtl.Value;
                    m = ph - cSz(4);
                    obj.slSecScroll.hCtl.Max = m;
                    obj.slSecScroll.hCtl.Value = max(m - pv, 0);
                    obj.slSecScroll.hCtl.SliderStep = [min(1,.1*cSz(4)/m) cSz(4)/m];
                else
                    obj.slSecScroll.hCtl.Visible = 'off';
                end
                obj.srcllCb();
            else
                if ~isempty(obj.hMdfSectionPanel)
                    while ~isempty(obj.hMdfSectionPanel.Children)
                        obj.hMdfSectionPanel.Children(1).Parent = [];
                    end
                    obj.slSecScroll.hCtl.Visible = 'off';
                end
            end
        end
        
        function deleteAllPages(obj)
            delete(obj.hAllPages);
            obj.hAllPages = [];
            
            delete(obj.hNewScanner);
            obj.hNewScanner = [];
            
            obj.hScannerPages = scanimage.guis.configuration.ScannerPage.empty;
        end
        
        function srcllCb(obj,varargin)
            if ~isempty(obj.hActivePage)
                obj.hActivePage.hPanel.Units = 'pixels';
                obj.hMdfSectionPanel.Units = 'pixels';
                
                ph = obj.hActivePage.hPanel.Position(4);
                ch = obj.hMdfSectionPanel.Position(4);
                
                if ph > ch
                    obj.hActivePage.hPanel.Position(1:2) = [0 -obj.slSecScroll.hCtl.Value];
                else
                    obj.hActivePage.hPanel.Position(1:2) = [0 ch-ph];
                end
            end
        end
        
        function scrollToTop(obj)
            obj.slSecScroll.hCtl.Value = obj.slSecScroll.hCtl.Max;
        end
        
        function initDaqInfo(obj)
            try
                hDaqSys = dabs.ni.daqmx.System;
            catch
                % daqmx is not installed
                hDaqSys.devNames = '';
            end
            dn = strtrim(hDaqSys.devNames);
            obj.daqInfo = scanimage.guis.configuration.DaqInfo.empty(1,0);
            
            if ~isempty(dn)
                deviceNames = strtrim(strsplit(dn,','))';
                
                for i = 1:numel(deviceNames)
                    obj.daqInfo(i) = scanimage.guis.configuration.DaqInfo.fromDaqmxDev(deviceNames{i});
                end

                obj.allDigChans = [obj.allDigChans; vertcat(obj.daqInfo.lines)];
                obj.allDigChans = sort(obj.allDigChans);
                obj.allDigChans = [obj.allDigChans; horzcat(obj.daqInfo.pfi)'];
                obj.allDigChans = unique(obj.allDigChans,'stable');
            end
            
            % RIO devices
            obj.simRioAdded = false;
            obj.rioInfo = dabs.ni.configuration.findFlexRios();
            obj.availableRios = fieldnames(obj.rioInfo);
            for i = 1:numel(obj.availableRios)
                nm = obj.availableRios{i};
                pn = strrep(obj.rioInfo.(nm).productName(1:end-1),' PXIe-','');
                obj.rioInfo.(nm).productName = pn;
                if ~isempty(strfind(pn,'NI517'))
                    obj.rioInfo.(nm).productName = strrep(pn(1:end-2),'R (','-');
                    obj.rioInfo.(nm).adapterModule = 'NI517x';
                    obj.rioInfo.(nm).desc = [nm ' (' obj.rioInfo.(nm).productName ')'];
                else
                    if ~isfield(obj.rioInfo.(nm), 'adapterModule')
                        obj.rioInfo.(nm).adapterModule = '';
                    end
                    adapterModule = strrep(obj.rioInfo.(nm).adapterModule,' ','');
                    adapterModule = strrep(adapterModule,'(-01)DC','');
                    obj.rioInfo.(nm).adapterModule = adapterModule;
                    obj.rioInfo.(nm).desc = [nm ' (' obj.rioInfo.(nm).productName ', ' adapterModule ')'];
                    
                    if obj.ADAPTER_MODULE_CHANNEL_COUNT.isKey(adapterModule)
                        obj.rioInfo.(nm).numAcqChans = obj.ADAPTER_MODULE_CHANNEL_COUNT(adapterModule);
                    else
                        obj.rioInfo.(nm).numAcqChans = 1;
                    end
                end
            end
            
            nVdaq = dabs.vidrio.rdi.Device.getDriverInfo.numDevices;
            for i = 1:nVdaq
                nm = sprintf('vDAQ%d',i-1);

                daqInfo_ = scanimage.guis.configuration.DaqInfo.fromVDaq(nm);
                obj.daqInfo(end+1) = daqInfo_;
                
                obj.availableRios{end+1} = nm;
                obj.rioInfo.(nm) = struct('productName','vDAQ','adapterModule','','desc',nm,'numAcqChans',4,'allDs',{daqInfo_.lines});
            end
            
            obj.addSimRio();
            
            bitfiles = dir(fullfile(scanimage.util.siRootDir,'+scanimage','FPGA','FPGA Bitfiles','*.lvbitx'));
            bitfiles = {bitfiles.name};
            obj.availableBitfiles = bitfiles;
            
            obj.findComPorts();
        end
        
        function updateDigitalOptions(obj)
            obj.allDigChans = unique(vertcat(obj.daqInfo.lines));
            obj.allInputDigChans = unique(vertcat(obj.daqInfo.ilines));
            obj.allOutputDigChans = unique(vertcat(obj.daqInfo.olines));
            
            maxNumPfis = max(vertcat(obj.daqInfo.numPFIs));
            if maxNumPfis
                allPfis = arrayfun(@(x)strcat('PFI',num2str(x)),0:maxNumPfis-1,'uniformoutput',false)';
                obj.allDigChans = [allPfis; obj.allDigChans];
                obj.allInputDigChans = [allPfis; obj.allInputDigChans];
                obj.allOutputDigChans = [allPfis; obj.allOutputDigChans];
            end
        end
        
        function initMotorSlmInfo(obj)
            obj.hMotorRegistry = scanimage.components.motors.legacy.MotorRegistry;
            obj.motorName2RegMap = containers.Map;
            ks = obj.hMotorRegistry.controllerMap.keys;
            for i = 1:numel(ks)
                dn = obj.hMotorRegistry.controllerMap(ks{i}).ListName;
                obj.motorName2RegMap(dn) = ks{i};
            end
            
            s = cell2mat(obj.hMotorRegistry.controllerMap.values);
            obj.fastZMotors = unique({s([s.SupportFastZ]).ListName});
            
            obj.hMotorRegistryNew = scanimage.components.motors.MotorRegistry();
            
            obj.slmName2RegMap = containers.Map;
            
        end
        
        function addSimRio(obj,force)
            sim = isempty(obj.availableDaqs) || all([obj.daqInfo.simulated]) || (nargin > 1 && force);
            if (obj.simulated || sim) && ~obj.simRioAdded
                if ~ismember('vDAQ0', obj.availableRios)
                    nm = 'vDAQ0';
                    
                    daqInfo_ = scanimage.guis.configuration.DaqInfo.simulatedVDaq(nm);
                    obj.daqInfo(end+1) = daqInfo_;
                    
                    obj.availableRios{end+1} = nm;
                    obj.rioInfo.(nm) = struct('productName','vDAQ','adapterModule','','desc',nm,'numAcqChans',4,'allDs',{daqInfo_.lines});
                end
                
%                 if ~ismember('RIO0', obj.availableRios)
%                     obj.rioInfo.RIO0 = struct('productName','NI7961','pxiNumber',1,'adapterModule','NI5734','desc','RIO0 (NI7961, NI5734)','numAcqChans',4);
%                     obj.availableRios{end+1} = 'RIO0';
%                 end
                
                obj.simRioAdded = true;
            end
            
            obj.availableRios = obj.availableRios(:);
            obj.rioChoices = cellfun(@(x)obj.rioInfo.(x).desc,obj.availableRios,'uniformoutput',false);
            obj.updateDigitalOptions();
        end
        
        function findComPorts(obj)
            obj.availableComPorts = arrayfun(@(x){sprintf('COM%d',x)},sort(dabs.generic.serial.findComPorts()));
        end
        
        function refreshPages(obj,varargin)
            % reload the mdf
            obj.hMDF.load(obj.hMDF.fMDFName);
            obj.mdfHdgs = {obj.hMDF.fHData(2:end).heading};
            remHdgs = obj.mdfHdgs;
            
            rem = cellfun(@(s)s(1)=='_',remHdgs);
            remHdgs(rem) = [];
            
            % clear unknown pages
            cellfun(@delete,obj.hOtherPages);
            obj.hOtherPages = {};
            obj.hAllPages = [];
            
            if isempty(remHdgs)
                obj.isWizardMode = true;
                obj.wizardDone = false;
                obj.wizardAddedMotors = false;
                obj.wizardAddedMotorHeadings = {};
                obj.wizardAddedFastZ = false;
                obj.wizardAddedPhotostim = false;
                obj.wizardAddedIntegration = false;
                obj.pageSeenBefore = {};
                
                delete(obj.hButtons);
                obj.hButtons = [];
                
                obj.hSIPage = scanimage.guis.configuration.SIPage(obj,true);
                obj.hShuttersPage = scanimage.guis.configuration.ShuttersPage(obj,true);
                obj.hBeamsPage = scanimage.guis.configuration.BeamsPage(obj,true);
                obj.hMotorsPage = scanimage.guis.configuration.MotorsPage(obj,true);
                obj.hFastZPage = scanimage.guis.configuration.FastZPage(obj,true);
                
                remHdgs = {'Motors' 'FastZ' 'CameraManager' 'Photostim' 'IntegrationRoiOutputs'};
                
                
                obj.hNewScanner = scanimage.guis.configuration.ScannerPage(obj,'',true);
            else
                obj.hSIPage = isPageThere('ScanImage', obj.hSIPage, @scanimage.guis.configuration.SIPage);
                obj.hShuttersPage = isPageThere('Shutters', obj.hShuttersPage, @scanimage.guis.configuration.ShuttersPage);
                obj.hBeamsPage = isPageThere('Beams', obj.hBeamsPage, @scanimage.guis.configuration.BeamsPage);
            end
            
            % see if the existing scanner pages are still there
            i = 1;
            while i <= numel(obj.hScannerPages)
                isPageThere(obj.hScannerPages(i).heading, obj.hScannerPages(i), @scanimage.guis.configuration.ScannerPage);
                if ~isvalid(obj.hScannerPages(i))
                    obj.hScannerPages(i) = [];
                else
                    i = i + 1;
                end
            end
            
            % search the mdf for new scanners
            i = 1;
            while i <= numel(remHdgs)
                if any(cellfun(@(s)~isempty(strfind(remHdgs{i},s)),obj.s2dNames))
                    obj.hScannerPages(end+1) = scanimage.guis.configuration.ScannerPage(obj,remHdgs{i});
                    remHdgs(i) = [];
                else
                    i = i+1;
                end
            end
            
            % search mdf for legacy motors
            legacyMotorMask = cellfun(@(s)~isempty(s),strfind(remHdgs,'LegacyMotor'));
            legacyMotorHeadings = remHdgs(legacyMotorMask);
            remHdgs(legacyMotorMask) = [];
            
            obj.hLegacyMotorsPage = {};
            for idx = 1:numel(legacyMotorHeadings)
                obj.hLegacyMotorsPage{end+1} = scanimage.guis.configuration.LegacyMotorPage(obj,legacyMotorHeadings{idx});
            end
            
            %repopulate scannerMap
            obj.scannerMap.remove(obj.scannerMap.keys);
            for i=1:length(obj.hScannerPages)
                page = obj.hScannerPages(i);
                obj.scannerMap(page.scannerName) = page;
            end
            
            obj.hMotorsPage = isPageThere('Motors', obj.hMotorsPage, @scanimage.guis.configuration.MotorsPage);
            obj.hFastZPage = isPageThere('FastZ', obj.hFastZPage, @scanimage.guis.configuration.FastZPage);
            obj.hPhotostimPage = isPageThere('Photostim', obj.hPhotostimPage, @scanimage.guis.configuration.PhotostimPage);
            obj.hIntegrationRoiOutputsPage = isPageThere('IntegrationRoiOutputs',obj.hIntegrationRoiOutputsPage, @scanimage.guis.configuration.IntegrationROIOutputsPage);
            obj.hThorLabsBScope2Page = isPageThere('Thorlabs BScope2', obj.hThorLabsBScope2Page, @scanimage.guis.configuration.ThorLabsBScope2Page);
            obj.hThorLabsECUScannersPage = isPageThere('Thorlabs ECU1', obj.hThorLabsECUScannersPage, @scanimage.guis.configuration.ThorLabsECUScannersPage);
            obj.hPMTControllersPage = isPageThere('GenericPmtController', obj.hPMTControllersPage, @scanimage.guis.configuration.PMTControllersPage);
            obj.hLSCPureAnalogPage = isPageThere('LSC Pure Analog', obj.hLSCPureAnalogPage, @scanimage.guis.configuration.LSCPureAnalogPage);
            
            
            % hide motor pages that only have comport entry
            if most.idioms.isValidObj(obj.hMotorsPage)
                remHdgs(ismember(remHdgs,obj.hMotorsPage.hideHeadings)) = [];
            end
            
            % remaining unexpected pages are configured with Generic table page.
            % Hence, need to have gui in above for it to populate            
            for i = 1:numel(remHdgs) 
                obj.hOtherPages{end+1} = scanimage.guis.configuration.GenericPage(obj,remHdgs{i});
            end
            % Need to have it here to appear as all pages and actually
            % create, worked before becuase it was being put into other
            % pages...
            obj.hAllPages = [obj.hSIPage, obj.hShuttersPage, obj.hBeamsPage, obj.hScannerPages, obj.hNewScanner, obj.hMotorsPage,...
                obj.hLegacyMotorsPage{:}, obj.hFastZPage, obj.hPhotostimPage, obj.hIntegrationRoiOutputsPage, obj.hThorLabsBScope2Page,... 
                obj.hThorLabsECUScannersPage, obj.hPMTControllersPage, obj.hLSCPureAnalogPage, obj.hOtherPages{:}];
            if obj.isWizardMode
                wizardPage = obj.selectedPage;
                
                scannerPageNames = {obj.hScannerPages.listLabel};
                if ~isempty(obj.hNewScanner)
                    scannerPageNames{end+1} = obj.hNewScanner.listLabel;
                end
                
                extraComps = {obj.hThorLabsBScope2Page obj.hThorLabsECUScannersPage obj.hPMTControllersPage};
                if obj.wizardAddedMotors
                    extraComps{end+1} = obj.hMotorsPage;
                    
                    hdgs = {obj.hAllPages.heading};
                    for jj = 1:numel(obj.wizardAddedMotorHeadings)
                        extraComps{end+1} = obj.hAllPages(strcmp(obj.wizardAddedMotorHeadings{jj},hdgs));
                    end
                end
                if obj.wizardAddedFastZ
                    extraComps{end+1} = obj.hFastZPage;
                end
                if obj.wizardAddedPhotostim
                    extraComps{end+1} = obj.hPhotostimPage;
                end
                if obj.wizardAddedIntegration
                    extraComps{end+1} = obj.hIntegrationRoiOutputsPage;
                end
                extraComps{end+1} = obj.hLSCPureAnalogPage;
                
                
                extraComps = horzcat(extraComps{:});
                if numel(extraComps)
                    extraComps = {extraComps.listLabel};
                end
                btns = [{'General ScanImage Settings' 'Shutter Configuration',...
                    'Power Modulation (Beams)'} scannerPageNames extraComps {'Additional Components'}];
                obj.recreateButtons(btns);
                
                if isempty(wizardPage)
                    wizardPage = 1;
                elseif wizardPage < numel(btns)
                    wizardPage = wizardPage + 1;
                end
                obj.selectedPage = wizardPage;
                
                if wizardPage == numel(btns)
                    % show the finishing page
                    obj.showFinishPage();
                else
                    hdg = obj.hActivePage.heading;
                    if ~isempty(hdg)
                        hdg = matlab.lang.makeValidName(hdg);
                        if ~ismember(hdg,obj.pageSeenBefore)
                            obj.pageSeenBefore{end+1} = hdg;
                            obj.hActivePage.applySmartDefaultSettings();
                        end
                    end
                end
            else
                obj.recreateButtons({obj.hAllPages.listLabel});
            end
            
            
            function [prop, validIdx] = isNamedPageThere(heading, prop, propFcn, expected)
                %NOTE: imports remHdgs readonly
                names = regexp(remHdgs, [regexptranslate('escape',heading) ' \((.+)\)'],...
                    'tokens', 'once');
                validIdx = ~cellfun('isempty', names);
                if ~any(validIdx)
                    return;
                end
                names(validIdx) = [names{validIdx}]; %bring valid strings up one level
                names(~validIdx) = {''}; %make names a proper cellstr
                remHdgs(validIdx) = [];
                
                %Definition of validIdx branches here.
                % Matched but unexpected Pages are simply not created, even as genericPages.
                if ~isempty(expected)
                    doUpdateIdx = ismember(names, expected);
                else
                    doUpdateIdx = validIdx;
                end
                %delete duplicate names 
                names = unique(names(doUpdateIdx));
                
                currPageNum = numel(prop);
                validPageNum = length(names);
                
                %refresh pages with new names
                for j=1:min(currPageNum, validPageNum)
                    prop{j}.reload(names{j});
                end
                
                %if currPageNum < validPageNum: Allocate
                for j=currPageNum+1:validPageNum
                    prop{j} = propFcn(obj, names{j});
                end
                
                %if validPageNum < currPageNum: Delete
                for j=validPageNum+1:currPageNum
                    delete(prop{j});
                end
                prop = prop(1:validPageNum);
            end
            
            function [hPage, validIdx] = isPageThere(heading, hPage, pageFcn)
                %NOTE: imports remHdgs readonly
                validIdx = strcmp(heading, remHdgs);
                if any(validIdx)
                    if most.idioms.isValidObj(hPage)
%                         hPage.reload();
                    else
                        hPage = pageFcn(obj);
                    end
                    remHdgs(validIdx) = [];
                else
                    most.idioms.safeDeleteObj(hPage);
                    hPage = [];
                end
            end
        end
        
        function showFinishPage(obj)
            obj.rawView = false;
            obj.selectedPage = numel(obj.hButtons);
            obj.wizardDone = true;
            obj.hActivePage = obj.hAdditionalComponentsPanel;
            obj.hAdditionalComponentsPanel.Parent = obj.hMdfSectionPanel;
            obj.resizePnl();
            obj.hTitleSt.String = 'Finish Setup';
            obj.hDescSt.String = 'Add any of the optional featured below or click finish to launch ScanImage. These features can also be added later.';
            obj.pbDelete.Visible = 'off';
        end
        
        function reportDaqUsage(obj)
            for hPg = obj.hAllPages
                obj.daqInfo = hPg.reportDaqUsage(obj.daqInfo);
            end
        end
        
        function mdfData = getCurrentMdfDataStruct(obj,heading)
            try
                obj.hMDF.load(obj.hMDF.fileName);
                [~,mdfData] = obj.hMDF.getVarsUnderHeading(heading);
            catch
                mdfData = [];
            end
        end
        
        function refreshRequired = applyVarStruct(obj,heading,varStruct,oldHeading)
            if nargin < 4
                oldHeading = '';
            end
            
            refreshRequired = false;
            
            if ~isempty(oldHeading) && ~strcmp(heading,oldHeading)
                obj.removeMdfSections({oldHeading});
                refreshRequired = true;
            end
            
            if ~ismember(heading,{obj.hMDF.fHData.heading})
                % create the new section
                obj.hMDF.generateDefaultSection(varStruct.z__modelClass,heading);
                refreshRequired = true;
            end
            
            if isfield(varStruct, 'z__modelClass')
                varStruct = rmfield(varStruct,'z__modelClass');
            end
            
            nms = fieldnames(varStruct);
            for i=1:numel(nms)
                obj.hMDF.writeVarToHeading(heading,nms{i},varStruct.(nms{i}),'',false);
            end
            obj.hMDF.updateFile();
        end
        
        function pbRevertCb(obj,varargin)
            if obj.isWizardMode
                v = obj.selectedPage;
                if v > 1
                    obj.selectedPage = v - 1;
                end
            else
                if strcmp(obj.hRawTable.Visible, 'on')
                    obj.refreshRawTable();
                else
                    obj.hActivePage.reload();
                end
            end
        end
        
        function pbApplyCb(obj,varargin)
            hAppliedPage = [];
            if strcmp(obj.hRawTable.Visible, 'on')
                obj.applyRawTable();
                refreshRequired = false;
            elseif isa(obj.hActivePage, 'scanimage.guis.configuration.ConfigurationPage')
                hAppliedPage = obj.hActivePage;
                oldHeading = hAppliedPage.heading;
                s = hAppliedPage.getNewVarStruct();
                if isempty(s)
                    return
                end
                refreshRequired = obj.applyVarStruct(obj.hActivePage.heading,s,oldHeading);
            end

            switch obj.hActivePage
                case obj.hSIPage
                    if obj.hSIPage.hasThorECU
                        if ~ismember('Thorlabs ECU1',obj.mdfHdgs)
                            obj.hThorLabsECUScannersPage = ...
                                scanimage.guis.configuration.ThorLabsECUScannersPage(obj,true);
                            refreshRequired = true;
                        end
                    else
                        if ismember('Thorlabs ECU1',obj.mdfHdgs)
                            % Page is here but not needed! remove it? hide the button?
                            %                         pc = true;
                        end
                    end
                    
                    if obj.hSIPage.hasBScope2
                        if ~ismember('Thorlabs BScope2',obj.mdfHdgs)
                            obj.hThorLabsBScope2Page = ...
                                scanimage.guis.configuration.ThorLabsBScope2Page(obj,true);
                            refreshRequired = true;
                        end
                    else
                        if ismember('Thorlabs BScope2',obj.mdfHdgs)
                            % Page is here but not needed! remove it? hide the button?
                            %                         pc = true;
                        end
                    end
                    
                    if obj.hSIPage.hasPMTController
                        if ~ismember('GenericPmtController',obj.mdfHdgs)
                            obj.hPMTControllersPage = ...
                                scanimage.guis.configuration.PMTControllersPage(obj,true);
                            if ~obj.isWizardMode
                                obj.hPMTControllersPage.applySmartDefaultSettings();
                            end
                            refreshRequired = true;
                        end
                    else
                        if ismember('GenericPmtController',obj.mdfHdgs)
                            % Page is here but not needed! remove it? hide the button?
                            %                         pc = true;
                        end
                    end
                case obj.hMotorsPage
                    obj.populateMotorsSection();
                    refreshRequired = true;
            end
            
            newScannerMade = ~isempty(obj.hNewScanner) && (obj.hActivePage == obj.hNewScanner);
            if newScannerMade
                obj.hScannerPages(end+1) = obj.hNewScanner;
                obj.hNewScanner = [];
            end
            
            if most.idioms.isValidObj(hAppliedPage)
                hAppliedPage.postApplyAction();
            end
            
            if obj.isWizardMode
                if obj.selectedPage == numel(obj.hButtons)
                    obj.isWizardMode = false;
                    
                    obj.contHit = true;
                    obj.Visible = false;
                    drawnow('nocallbacks');
                elseif obj.selectedPage == 1
                    obj.addSimRio();
                end
                
                obj.refreshPages();
                
                if obj.wizardDone && newScannerMade
                    obj.showFinishPage();
                end
            elseif refreshRequired
                obj.refreshPages();
                obj.selectedPage = find(strcmp({obj.hAllPages.listLabel}, obj.hActivePage.listLabel));
            end
            
            obj.notify('mdfUpdate');
            
            function [hPages, doRefresh] = reloadDepPages(hPages, pageNames, constructor)
                currPageNum = numel(hPages);
                newPageNum = length(pageNames);
                doRefresh = currPageNum < newPageNum;
                
                %refresh
                for i=1:min(currPageNum, newPageNum)
                    hPages{i}.reload(pageNames{i});
                end
                
                %instantiate
                for i=currPageNum+1:newPageNum
                    hPages{i} = constructor(obj, pageNames{i}, true);
                end
                
                %do not delete because that's handled by refreshPage
            end
        end
        
        function pbOkCb(obj,varargin)
            if obj.hActivePage == obj.hNewScanner
                obj.pbApplyCb();
            end
            
            for hPage = obj.hAllPages
                if ~strcmp(obj.hRawTable.Visible, 'on') || hPage ~= obj.hActivePage
                    oldHeading = hPage.heading;
                    s = hPage.getNewVarStruct();
                    obj.applyVarStruct(hPage.heading,s,oldHeading);
                    hPage.postApplyAction();
                end
            end
            
            if strcmp(obj.hRawTable.Visible, 'on')
                obj.applyRawTable();
            end
            
            obj.Visible = false;
            obj.contHit = true;
            obj.notify('mdfUpdate');
        end
        
        function deleteScanner(obj,varargin)
            isNewScanner = obj.hNewScanner == obj.hActivePage;
            if isNewScanner
                msg = 'Are you sure you want to discard these settings and cancel creation of new scanner?';
            else
                msg = sprintf('Are you sure you want to delete the scanner ''%s''? All associated settings will be permanently removed from the microscope configuration.',obj.hActivePage.scannerName);
            end
            
            resp = questdlg(msg, 'Remove Scanner', 'Yes', 'Cancel', 'Cancel');
            
            if strcmp(resp,'Yes')
                if isNewScanner
                    for i =1 :numel(obj.hAllPages)
                        if obj.hAllPages(i) == obj.hNewScanner
                            obj.hAllPages(i) = [];
                            break
                        end
                    end
                    most.idioms.safeDeleteObj(obj.hNewScanner);
                    obj.hNewScanner = [];
                else
                    obj.removeMdfSections({obj.hActivePage.heading});
                    obj.refreshPages();
                end
                
                if obj.isWizardMode
                    obj.showFinishPage();
                else
                    obj.selectedPage = 1;
                end
            end
        end
        
        function newScanner(obj,varargin)
            if isempty(obj.hNewScanner) || ~most.idioms.isValidObj(obj.hNewScanner)
                obj.hNewScanner = scanimage.guis.configuration.ScannerPage(obj,'',true);
            end
            
            set(obj.hButtons, 'Value', false);
            obj.activatePage(obj.hNewScanner);
            obj.pbDelete.Visible = 'on';
            
            if obj.isWizardMode
                obj.pbApply.String = 'Next';
            end
        end
        
        function recreateButtons(obj,nms)
            delete(obj.hButtons);
            obj.hButtons = [];
            for i = 1:numel(nms)
                obj.hButtons(end+1) = uicontrol('parent',obj.hButtonFlow,'string',nms{i},'style','toggleButton','callback',@obj.buttCb,'userdata',i,'FontSize',10);
            end
            set(obj.hButtons, 'HeightLimits', [10 50]);
            
            if obj.isWizardMode && ~obj.wizardDone
                set(obj.hButtons, 'Enable', 'off');
            end
            %need some style!
            
            obj.hButtons = handle(obj.hButtons);
        end
        
        function buttCb(obj,src,~)
            i = src.UserData;
            if obj.isWizardMode && i == numel(obj.hButtons)
                obj.showFinishPage();
            else
                obj.selectedPage = i;
            end
        end
        
        function scrollWheelFcn(obj,~,evt)
            obj.hFig.Units = 'pixels';
            x = obj.hFig.CurrentPoint(1);
            
            if x > obj.buttonsWidth
                v = obj.slSecScroll.hCtl.Value - 50*evt.VerticalScrollCount;
                v = max(min(v,obj.slSecScroll.hCtl.Max),obj.slSecScroll.hCtl.Min);
                obj.slSecScroll.hCtl.Value = v;
            elseif ~obj.isWizardMode
                n = numel(obj.hAllPages);
                if n
                    sp = obj.selectedPage;
                    i = sp + sign(evt.VerticalScrollCount);
                    i = max(min(i,n),1);
                    if i ~= sp
                        obj.selectedPage = i;
                    end
                end
            end
        end
        
        function keyPressFcn(obj,~,evt)
            if ~obj.isWizardMode && ~obj.hActivePage.isGeneric && ismember('control',evt.Modifier) && strcmp(evt.Key,'r')
                obj.rawView = ~obj.rawView;
            end
        end
        
        function tfContinue = doModalSectionEdit(obj,page)
            obj.init();
            
            obj.contHit = false;
            obj.pbApply.Visible = 'off';
            obj.pbAdd.Visible = 'off';
            obj.pbOk.String = 'Continue';
            
            try
                obj.selectedPage = page;
                obj.pbDelete.Visible = 'off';
                obj.Visible = true;
                waitfor(obj.hFig,'Visible','off');
                drawnow();
            catch ME
                obj.pbApply.Visible = 'on';
                obj.pbAdd.Visible = 'on';
                obj.pbOk.String = 'Ok';
                ME.rethrow();
            end
            
            obj.pbApply.Visible = 'on';
            obj.pbAdd.Visible = 'on';
            obj.pbOk.String = 'Ok';
            
            tfContinue = obj.contHit;
        end
        
        function refreshRawTable(obj)
            try
                obj.hMDF.load(obj.hMDF.fileName);
                rows = obj.hMDF.getRowsForHeading(obj.hActivePage.heading);
            catch
            end
            
            em = cellfun(@(x)isempty(strtrim(x)),rows);
            rows(em) = [];
            dat = cellfun(@(s)splitRow(s),rows(2:end),'uniformoutput',false);
            obj.hRawTable.Data = [vertcat(dat{:}); {false '' '' ''}];
            
            function c = splitRow(s)
                c1 = findComment(s);
                c2 = findeqls(c1{1});
                
                c = [{false} c2 c1(2)];
                
                function c = findComment(s)
                    ccnt = 0;
                    
                    for i = 1:length(s)
                        if s(i) == ''''
                            ccnt = ccnt + 1;
                        end
                        
                        if ~mod(ccnt,2) && s(i) == '%'
                            for j = i+1:length(s);
                                if s(j) ~= '%'
                                    c = {strtrim(s(1:i-1)) strtrim(s(j:end))};
                                    return;
                                end
                            end
                            c = {strtrim(s(1:i-1)) ''};
                            return;
                        end
                    end
                    c = {strtrim(s) ''};
                end
                
                function c = findeqls(s)
                    for i = 1:length(s)
                        if s(i) == '='
                            c = {strtrim(s(1:i-1)) strtrim(s(i+1:end))};
                            if c{2}(end) == ';'
                                c{2}(end) = [];
                            end
                            return;
                        end
                    end
                    c = {strtrim(s) ''};
                end
            end
        end
        
        function rawTableCellEditFcn(obj,~,evt)
            dat = obj.hRawTable.Data;
            
            % make sure there is a blank row
            if size(dat,1) < 1
                lr = [];
            else
                lr = dat(end,:);
            end
            
            if isempty(lr) || ~isempty(lr{2}) || ~isempty(lr{3}) || ~isempty(lr{4})
                dat(end+1,:) = {false '' '' ''};
                obj.hRawTable.Data = dat;
            end
        end
        
        function applyRawTable(obj)
            dat = obj.hRawTable.Data;
            
            for i = 1:size(dat,1)-1
                var = dat{i,2};
                if ~isempty(var)
                    if dat{i,1}
                        obj.hMDF.removeVarFromHeading(obj.hActivePage.heading,var);
                    else
                        if isempty(dat{i,4})
                            cm = '';
                        else
                            cm = ['    %' dat{i,4}];
                        end
                        obj.hMDF.writeVarToHeading(obj.hActivePage.heading,var,eval(dat{i,3}),cm,false);
                    end
                end
            end
            
            obj.hMDF.updateFile();
            obj.refreshRawTable();
        end
        
        function daqName = getScannerGalvoDaq(obj,scannerName)
            daqName = '';
            
            if obj.scannerMap.isKey(scannerName)
                hPg = obj.scannerMap(scannerName);
                if most.idioms.isValidObj(hPg)
                    daqName = strtrim(hPg.galvoDaq);
                end
            end
        end
        
        function daqName = getScannerGalvoFeedbackDaq(obj,scannerName)
            daqName = '';
            
            if obj.scannerMap.isKey(scannerName)
                hPg = obj.scannerMap(scannerName);
                if most.idioms.isValidObj(hPg)
                    daqName = strtrim(hPg.galvoFeedbackDaq);
                end
            end
        end
        
        function populateMotorsSection(obj)
            [~, mtrs] = obj.hMDF.getVarsUnderHeading('Motors');
            mtrs = mtrs.motors;
            
            % filter for invalid MDF entries
            invalidMask = arrayfun(@(m)isempty(m.name) || isempty(m.controllerType),mtrs);
            mtrs(invalidMask) = [];
            
            motorRegistryEntries = cellfun(@(c)scanimage.components.motors.MotorRegistry.searchEntry(c),{mtrs.controllerType},'UniformOutput',false);
            emptyMask = cellfun(@(e)isempty(e),motorRegistryEntries);
            mtrs(emptyMask) = [];
            motorRegistryEntries(emptyMask) = [];
            motorRegistryEntries = horzcat(motorRegistryEntries{:});
            
            if ~isempty(motorRegistryEntries)
                % filter for motor controllers that require MDF
                metaClasses = {motorRegistryEntries.metaClass};
                isMdfMask = cellfun(@(mc)ismember('most.HasMachineDataFile',{mc.SuperclassList.Name}),metaClasses);
                
                mtrs(~isMdfMask) = [];
                metaClasses(~isMdfMask) = [];
                
                % add MDF headings if necessary
                mdfHeadings = cellfun(@(mc)eval([mc.Name '.mdfHeading']),metaClasses,'UniformOutput',false);
                for idx = 1:numel(mtrs)
                    heading = sprintf('%s (%s)',mdfHeadings{idx},mtrs(idx).name);
                    if ~ismember(heading,{obj.hMDF.fHData.heading})
                        obj.addMdfSectionToFile(metaClasses{idx}.Name,heading);
                        obj.wizardAddedMotorHeadings{end+1} = heading;
                    end
                end
            end
        end

        function addMdfSectionToFile(obj,modelClass,varargin)
           obj.hMDF.generateDefaultSection(modelClass,varargin{:});
           
           obj.hMDF.load(obj.hMDF.fMDFName);
           obj.mdfHdgs = {obj.hMDF.fHData(2:end).heading};
        end
        
        function removeMdfSections(obj,hdingsToRemove)
            obj.hMDF.removeSections(hdingsToRemove);
            obj.hMDF.load(obj.hMDF.fMDFName);
        end
        
        function migrateSettings(obj)
            % migrate old format of motor and fast z settings
            hdgs = {obj.hMDF.fHData(2:end).heading};
            fileBacked = false;
            
            if ismember('ScanImage',hdgs)
                [~, si] = obj.hMDF.getVarsUnderHeading('ScanImage');
                
                if isfield(si, 'scannerNames')
                    backupMdf();
                    keepScanners = si.scannerNames;
                    obj.hMDF.removeVarFromHeading('ScanImage','scannerNames');
                    obj.hMDF.removeVarFromHeading('ScanImage','scannerTypes');
                    
                    s2dp = 'scanimage/components/scan2d';
                    list = what(s2dp);
                    list = list(1); % workaround for sparsely occuring issue where list is a 2x1 structure array, where the second element is empty
                    s2dp = [strrep(s2dp,'/','.') '.'];
                    names = cellfun(@(x)[s2dp x(1:end-2)],list.m,'UniformOutput',false);
                    s2dTypes = strrep(names,'scanimage.components.scan2d.','');
                    
                    scannerHeadings = regexp({obj.hMDF.fHData.heading},'^(.+)\((.+)\)','tokens');
                    isScanner = ~cellfun(@isempty,scannerHeadings);
                    
                    for i = find(isScanner)
                        type = strtrim(scannerHeadings{i}{1}{1});
                        motorName = scannerHeadings{i}{1}{2};
                        if ismember(type, s2dTypes) && ~ismember(motorName, keepScanners)
                            hdg = obj.hMDF.fHData(i).heading;
                            obj.hMDF.renameSection(hdg, ['_' hdg]);
                        end
                    end
                    
                    msgbox('Scanner settings have been migrated from an older format. Please check the settings for accuracy.','Settings Migration','warn');
                end
            end
            
            motorFmt1 = false; %% oldest motor format with fields for motor and motor2
            motorFmt2 = false; %% old format with with struct array for motor definitions
            if ismember('Motors',hdgs)
                [~, mtrs] = obj.hMDF.getVarsUnderHeading('Motors');
                motorFmt1 = isfield(mtrs,'motorControllerType');
                motorFmt2 = ~isfield(mtrs,'scaleXYZ');
                if motorFmt1 || motorFmt2
                    backupMdf();
                    obj.removeMdfSections({'Motors'});
                    obj.addMdfSectionToFile('scanimage.components.Motors');
                end
            end
            
            oldFastZFmt = false;
            if ismember('FastZ',hdgs)
                [~, fzs] = obj.hMDF.getVarsUnderHeading('FastZ');
                if isfield(fzs,'fastZControllerType')
                    oldFastZFmt = true;
                    backupMdf();
                    obj.removeMdfSections({'FastZ'});
                    obj.addMdfSectionToFile('scanimage.components.FastZ');
                end
            end
            
            if oldFastZFmt
                s = struct;
                
                if strcmp(fzs.fastZControllerType, 'useMotor2') && motorFmt1
                    s.actuators.controllerType = mtrs.motor2ControllerType;
                    s.actuators.comPort = mtrs.motor2COMPort;
                    
                    if ~isempty(mtrs.motor2BaudRate)
                        s.customArgs = {'baudRate' mtrs.motor2BaudRate};
                    end
                    
                    mtrs.motor2ControllerType = '';
                else
                    s.actuators.controllerType = fzs.fastZControllerType;
                    s.actuators.comPort = fzs.fastZCOMPort;
                    
                    if ~isempty(fzs.fastZBaudRate)
                        s.customArgs = {'baudRate' fzs.fastZBaudRate};
                    end
                end
                
                s.actuators.daqDeviceName = fzs.fastZDeviceName;
                s.actuators.frameClockIn = fzs.frameClockIn;
                s.actuators.cmdOutputChanID = fzs.fastZAOChanID;
                s.actuators.sensorInputChanID = fzs.fastZAIChanID;
                
                if strcmp(s.actuators.controllerType, 'analog') && ismember('LSC Pure Analog',hdgs)
                    [~, ana] = obj.hMDF.getVarsUnderHeading('LSC Pure Analog');
                    
                    s.actuators.commandVoltsPerMicron = ana.commandVoltsPerMicron;
                    s.actuators.sensorVoltsPerMicron = ana.sensorVoltsPerMicron;
                    s.actuators.commandVoltsOffset = ana.commandVoltsOffset;
                    s.actuators.sensorVoltsOffset = ana.sensorVoltsOffset;
                    s.actuators.maxCommandVolts = ana.maxCommandVolts;
                    s.actuators.maxCommandPosn = ana.maxCommandPosn;
                    s.actuators.minCommandVolts = ana.minCommandVolts;
                    s.actuators.minCommandPosn = ana.minCommandPosn;
                    
                    if isempty(s.actuators.daqDeviceName)
                        s.actuators.daqDeviceName = ana.analogCmdBoardID;
                    end
                    
                    if isempty(s.actuators.cmdOutputChanID)
                        s.actuators.cmdOutputChanID = ana.analogCmdChanIDs;
                    end
                    
                    if isempty(s.actuators.sensorInputChanID)
                        s.actuators.sensorInputChanID = ana.analogSensorChanIDs;
                    end

                    obj.removeMdfSections({'LSC Pure Analog'});
                end
                
                obj.applyVarStruct('FastZ',s);
            end
            
            if motorFmt1
                % two-stepConversion via motorFmt2
                s = struct;
                
                if ~isempty(mtrs.motorControllerType) && ~strcmp('dummy', mtrs.motorControllerType)
                    s.motors = motorStructFmt2(mtrs,'motor');
                end
                
                if ~isempty(mtrs.motor2ControllerType) && ~strcmp('dummy', mtrs.motor2ControllerType)
                    m = motorStructFmt2(mtrs,'motor2');
                    if isfield(s,'motors')
                        s.motors(2) = m;
                    else
                        s.motors = m;
                    end
                end
                
                mtrs = s;
                motorFmt1 = false;
                motorFmt2 = true;
            end
            
            if motorFmt2
                motorRegistryEntry = scanimage.components.motors.MotorRegistry.searchEntry('LegacyMotor');
                
                s = struct;
                
                s.scaleXYZ = [1 1 1];
                s.axisMovesObjective = [false false false];
                s.motors = struct('name',{},'controllerType',{},'dimensions',{});
                
                if isfield(mtrs,'motors')
                    for idx = 1:numel(mtrs.motors)
                        motor = mtrs.motors(idx);
                        if ~isempty(motor.controllerType)
                            motorName = sprintf('Motor %d',numel(s.motors)+1);
                            s.motors(end+1) = struct(...
                                'name',motorName,...
                                'controllerType','LegacyMotor',...
                                'dimensions',motor.dimensions);
                            
                            motor = rmfield(motor,'dimensions');
                            
                            % add LegacyMotor MDF section for motor
                            headingName = sprintf('LegacyMotor (%s)',motorName);
                            obj.addMdfSectionToFile(motorRegistryEntry.className,headingName);
                            [~, mtr] = obj.hMDF.getVarsUnderHeading(headingName);
                            mtr = motor;
                            obj.applyVarStruct(headingName,mtr);
                        end
                    end
                end
                
                if isempty(s.motors)
                    s.motors = struct('name','','controllerType','','dimensions','');
                end                
                
                obj.applyVarStruct('Motors',s);
                
                obj.populateMotorsSection();
            end
            
            if motorFmt1 || motorFmt2 || oldFastZFmt
                msgbox('Motor and FastZ settings have been migrated from an older format. Please check the settings for accuracy.','Settings Migration','warn');
            end
            
            function s = motorStructFmt2(in,pfx)
                s.controllerType = in.([pfx 'ControllerType']);
                
                if isfield(in,[pfx 'Dimensions'])
                    if isempty(in.([pfx 'Dimensions']))
                        s.dimensions = 'XYZ';
                    else
                        s.dimensions = in.([pfx 'Dimensions']);
                    end
                else
                    % motor 2 did not have this field and motor 2 is always a Z motor
                    s.dimensions = 'Z';
                end
                
                s.comPort = in.([pfx 'COMPort']);
                
                if isempty(in.([pfx 'BaudRate']))
                    s.customArgs = {};
                else
                    s.customArgs = {'baudRate' in.([pfx 'BaudRate'])};
                end
                
                if ~isempty(in.([pfx 'StageType']))
                    s.customArgs = [s.customArgs {'stageType' in.([pfx 'StageType'])}];
                end
                s.invertDim = repmat('+',1,numel(s.dimensions));
                
                if isfield(in, [pfx 'USBName']) && ~isempty(in.([pfx 'USBName']))
                    s.customArgs = [s.customArgs {'usbName' in.([pfx 'USBName'])}];
                end
                
                s.positionDeviceUnits = in.([pfx 'PositionDeviceUnits']);
                s.velocitySlow = in.([pfx 'VelocitySlow']);
                s.velocityFast = in.([pfx 'VelocityFast']);
                s.moveCompleteDelay = mtrs.moveCompleteDelay;
                s.moveTimeout = [];
                s.moveTimeoutFactor = [];
            end
            
            function backupMdf()
                if ~fileBacked
                    [pth, nm] = fileparts(obj.hMDF.fMDFName);
                    newName = fullfile(pth,[nm '.bak.' datestr(now,'yyyy-mm-dd-HHMMSS') '.m']);
                    copyfile(obj.hMDF.fMDFName, newName);
                    fileBacked = true;
                end
            end
        end
    end
    
    methods
        function v = get.availableDaqs(obj)
            v = {obj.daqInfo.deviceName}';
        end
        
        function v = get.scannerNames(obj)
            mask = ~cellfun(@isempty,{obj.hScannerPages.heading});
            v = {obj.hScannerPages(mask).scannerName}';
        end
        
        function v = get.scannerCanLinearScan(obj)
            mask = ~cellfun(@isempty,{obj.hScannerPages.heading});
            v = [obj.hScannerPages(mask).canLinearScan]';
        end
        
        function v = get.scannerCanPhotostim(obj)
            mask = ~cellfun(@isempty,{obj.hScannerPages.heading});
            v = [obj.hScannerPages(mask).canPhotostim]';
        end
        
        function v = get.scannerIsResonant(obj)
            mask = ~cellfun(@isempty,{obj.hScannerPages.heading});
            v = [obj.hScannerPages(mask).scannerTypeSel]' < 3;
        end
        
        function v = get.numShutters(obj)
            if isempty(obj.hShuttersPage)
                v = 0;
            else
                v = obj.hShuttersPage.numShutters;
            end
        end
        
        function v = get.shutterNames(obj)
            if isempty(obj.hShuttersPage)
                v = {};
            else
                v = obj.hShuttersPage.shutterNames;
            end
        end
        
        function v = get.numBeamDaqs(obj)
            if isempty(obj.hBeamsPage)
                v = 0;
            else
                v = numel(obj.hBeamsPage.beamDaqNames);
            end
        end
        
        function v = get.beamDaqNames(obj)
            if isempty(obj.hBeamsPage)
                v = {};
            else
                v = obj.hBeamsPage.beamDaqNames;
            end
        end
        
        function v = get.beams(obj)
            if isempty(obj.hBeamsPage)
                v = {};
            else
                v = obj.hBeamsPage.beams;
            end
        end
        
        function v = get.simulated(obj)
            if isempty(obj.hSIPage) || ~most.idioms.isValidObj(obj.hSIPage)
                v = false;
            else
                v = obj.hSIPage.simulated;
            end
        end
        
        function set.isWizardMode(obj,v)
            obj.isWizardMode = v;
            
            obj.constructAddlCompsPnl();
            
            if obj.initDone
                obj.pbOk.Visible = obj.tfMap(~v);
                
                if v
                    obj.pbRevert.String = 'Previous';
                else
                    obj.pbApply.String = 'Apply';
                    obj.pbRevert.String = 'Revert';
                end
            
                obj.pbAdd.Visible = ~v;
            end
        end
        
        function set.rawView(obj,v)
            obj.rawView = v;
            
            obj.hSecPanel.Visible = obj.tfMap(~v);
            obj.hRawTable.Visible = obj.tfMap(v);
            if v
                obj.refreshRawTable();
            end
        end
        
        function v = get.selectedPage(obj)
            vs = get(obj.hButtons, 'Value');
            if isempty(vs)
                v = [];
            else
                v = find([vs{:}],1);
            end
        end
        
        function set.selectedPage(obj,btnIdx)
            set(obj.hButtons, 'Value', false);
            if isempty(btnIdx)
                btnIdx = 1;
                [tfPg,pgIdx] = ismember(get(obj.hButtons(btnIdx),'String'),{obj.hAllPages.listLabel});
            elseif ischar(btnIdx)
                [tfPg,pgIdx] = ismember(btnIdx,{obj.hAllPages.heading});
                if ~tfPg
                    [tfPg,pgIdx] = ismember(btnIdx,{obj.hAllPages.listLabel});
                    if ~tfPg
                        return
                    end
                end
                
                [~,btnIdx] = ismember(obj.hAllPages(pgIdx).listLabel,{obj.hButtons.String});
            else
                [tfPg,pgIdx] = ismember(obj.hButtons(btnIdx).String,{obj.hAllPages.listLabel});
            end
            
            if btnIdx
                set(obj.hButtons(btnIdx), 'Value', true);
            end
            
            if obj.isWizardMode
                set(obj.hButtons(1:btnIdx), 'Enable', 'on');
                if btnIdx == numel(obj.hButtons)
                    obj.pbApply.String = 'Finish';
                else
                    obj.pbApply.String = 'Next';
                end
            end
            
            set(obj.hMdfSectionPanel.Children, 'Parent', []);
            
            if tfPg
                obj.activatePage(obj.hAllPages(pgIdx));
            end
        end
        
        function activatePage(obj, hPg)
            obj.hActivePage = hPg;
            
            obj.hTitleSt.String = obj.hActivePage.listLabel;
            obj.hDescSt.String = obj.hActivePage.descriptionText;
            
            obj.hActivePage.refreshPageDependentOptions();
            if obj.hActivePage.isGeneric
                obj.hSecPanel.Visible = obj.tfMap(false);
                obj.hRawTable.Visible = obj.tfMap(true);
                obj.refreshRawTable();
            else
                obj.rawView = obj.rawView;
            end
            
            obj.hActivePage.hPanel.Parent = obj.hMdfSectionPanel;
            obj.pbDelete.Visible = isa(obj.hActivePage, 'scanimage.guis.configuration.ScannerPage') && (numel(obj.hScannerPages) > 1);
            
            obj.resizePnl();
            obj.scrollToTop();
        end
    end
end


%--------------------------------------------------------------------------%
% ConfigurationEditor.m                                                    %
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
