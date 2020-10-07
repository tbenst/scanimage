classdef SlmLutPixelPolynomials < scanimage.mroi.scanners.slmLut.SlmLut
    properties
        lut = []
        MSE = []
    end
    
    properties (SetAccess = immutable)
        useGpu = false;
    end
    
    methods
        function obj = SlmLutPixelPolynomials(lut)
            obj.useGpu = most.util.gpuComputingAvailable();
            
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
            
            if obj.useGpu
                pixelVals = obj.applyGpu(phis);
            else
                pixelVals = obj.applyCpu(phis);
            end
        end
        
        function plot(obj)
            hFig = figure('NumberTitle','off','Name','Pixelwise Lut');
            hFig.WindowButtonMotionFcn = @updateLut;
            hFig.WindowScrollWheelFcn = @incPhi;
            
            topFlow = most.gui.uiflowcontainer('Parent',hFig,'FlowDirection','LeftToRight');
                leftFlow = most.gui.uiflowcontainer('Parent',topFlow,'FlowDirection','TopDown');
                    imFlow = most.gui.uiflowcontainer('Parent',leftFlow,'FlowDirection','LeftToRight');
                    sliderFlow = most.gui.uiflowcontainer('Parent',leftFlow,'FlowDirection','LeftToRight');
                        set(sliderFlow,'HeightLimits',[20 20]);
                plotFlow = most.gui.uiflowcontainer('Parent',topFlow,'FlowDirection','TopDown');
                    set(plotFlow,'WidthLimits',[200 300]);
            
            res = [size(obj.lut,1),size(obj.lut,2)];
             
            %%% image
            hAxIm = axes('Parent',imFlow,'DataAspectRatio',[1 1 1],'XTick',[],'YTick',[]);
            box(hAxIm,'on');
            view(hAxIm,0,-90);
            hAxIm.XLim = [1 res(1)];
            hAxIm.YLim = [1 res(2)];
            hAxIm.CLim = [0 255];
            hSurfCam = surface('Parent',hAxIm,'FaceColor','texturemap','EdgeColor','none','CData',[],'Hittest','off','PickableParts','none');
            colorbar(hAxIm);
            
            [xx,yy,zz] = meshgrid([1 res(1)],[1 res(2)],0);
            xx = xx';
            yy = yy';
            zz = zz';
            
            hSurfCam.XData = xx;
            hSurfCam.YData = yy;
            hSurfCam.ZData = zz;
            
            %%% slider
            hSlPhiVal = uicontrol('Parent',sliderFlow,'Style','slider','Callback',@updateImage);
            
            %%% lut
            hAxLut = axes('Parent',plotFlow);
            hAxLut.XLim = [0 2*pi];
            hAxLut.YLim = [0 255];
            title(hAxLut,'LUT');
            xlabel(hAxLut,'Phi');
            ylabel(hAxLut,'SLM Pixel Value');
            box(hAxLut,'on');
            grid(hAxLut,'on');
            
            hLineLutRaw = line('Parent',hAxLut,'XData',[],'YData',[]);
            hTextLut = text('Parent',hAxLut,'String','','VerticalAlignment','top','HorizontalAlignment','left','Color',[0 0 0]);
            hTextLut.Position = [0 hAxLut.YLim(2)];
            
            updateImage();
            updateLut();
            
            function incPhi(src,evt)
                inc = -sign(evt.VerticalScrollCount) * 0.01;
                
                val = hSlPhiVal.Value;
                val = val + inc;
                val = max(0,min(1,val));
                hSlPhiVal.Value = val;
                
                updateImage();
            end
            
            function updateImage(varargin)
                phi = hSlPhiVal.Value*(2*pi-1e-6);
                im = phi * ones(res(1),res(2),'single');
                im = obj.apply(im);
                im = gather(im);
                
                hSurfCam.CData = im;
                title(hAxIm,sprintf('Phi: %.2f',phi));
            end
            
            function updateLut(varargin)
                pt = hAxIm.CurrentPoint(1,1:2);
                pt = round(pt);
                
                if pt(1)>=1 && pt(1)<=res(1) && pt(2)>=1 && pt(2)<=res(2)
                    P = squeeze(obj.lut(pt(1),pt(2),:));
                    P = gather(P);
                    
                    phi = linspace(0,2*pi,100);
                    pp = polyval(flipud(P),phi);
                    
                    hLineLutRaw.XData = phi;
                    hLineLutRaw.YData = pp;
                    hTextLut.String = sprintf(' [%d,%d]',pt(1),pt(2));
                end
            end
        end
    end
    
    methods (Access = protected) 
        function s = saveInternal(obj)
            s = struct();
            s.lut = gather(obj.lut);
            s.MSE = gather(obj.MSE);
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
    end
    
    methods (Access = private)
        function pixelVals = applyGpu(obj,phis)
            phis = gpuArray(phis);
            pixelVals = scanimage.mroi.scanners.slmLut.applyPolyLutGpu(phis,obj.lut);
        end
        
        function pixelVals = applyCpu(obj,phis)
            phis = mod(phis,2*pi);
            
            degree = size(obj.lut,3)-1;
            pwrs = single(0:degree);
            pwrs = shiftdim(pwrs(:),-2);
            
            phis = bsxfun(@power,phis,pwrs);
            
            pixelVals = obj.lut .* phis;
            pixelVals = sum(pixelVals,3);
        end
    end
    
    methods
        function set.lut(obj,val)
            val = single(val);
            
            if obj.useGpu
               val = gpuArray(val); 
            end
            
            obj.lut = val;
        end
    end
end


%--------------------------------------------------------------------------%
% SlmLutPixelPolynomials.m                                                 %
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
