classdef TreeNode < most.util.Uuid
    properties
        hParent;
    end
    
    properties (SetAccess = private)
        hChildren = {};
    end
    
    properties (Access = private)
        hParentBeingDestroyedListener;
        hChildBeingDestroyedListeners;
        
        tnClassName = mfilename('class');
    end
    
    events
        treeChanged;
    end
    
    methods
        function obj = TreeNode()
        end
        
        function delete(obj)
            most.idioms.safeDeleteObj(obj.hParentBeingDestroyedListener);
            most.idioms.safeDeleteObj(obj.hChildBeingDestroyedListeners);
        end
    end
    
    %% User methods
    methods
        function str = getDisplayInfo(obj)
            str = 'TreeNode';
        end
        
        function plotTree(obj,hParent)
            if nargin < 2 || isempty(hParent)
                hFig = figure('Name','Tree','NumberTitle','off');
                hParent = axes('Parent',hFig,'DataAspectRatio',[1 2 1],'Visible','off');
            end
            
            [parents,nodes] = obj.getTree();
            
            [xx,yy,h,s] = treelayout(parents);
            h = numel(unique(yy))-1;
            pts = [xx(:),yy(:)];
            pts(:,2) = pts(:,2);            
            pts = pts-min(pts);
            maxPts = max(pts);
            maxPts(maxPts==0) = 1;
            pts = pts./max(maxPts);
            
            w = getTreeLayoutWidth(pts(:,1),pts(:,2));
            pts = pts .* [w h]; 
            
            boxSize = [0.75 0.6];
            
            for idx = 1:length(nodes)
                makeInfobox(nodes{idx},pts(idx,:));
                
                if idx >= 2
                    parentIdx = parents(idx);
                    startPt = pts(parentIdx,:);
                    endPt = pts(idx,:);
                    drawConnection(startPt,endPt);
                end
            end
            
            %%% local functions
            function makeInfobox(node,pt)
                hRect = rectangle('Parent',hParent,'Position',[pt-boxSize/2 boxSize],'Curvature',0.1,'FaceColor',[1 1 1]*0.95);
                hRect.ButtonDownFcn = @(varargin)buttonDownFcn(node);
                
                if node.isequal(obj)
                    hRect.FaceColor(1) = 1;
                    hRect.EdgeColor = 'r';
                end
                hText = text('Parent',hParent,'Position',[pt,0],'String',node.getDisplayInfo(),'HorizontalAlignment','center','VerticalAlignment','middle','Hittest','off','PickableParts','none');
                
                function buttonDownFcn(node)
                    assignin('base','node',node);
                    link = '<a href ="matlab:evalin(''base'',''node'');">node</a>';
                    fprintf('------------------------\n');
                    fprintf(2,'Assigned %s in base.\n\n', link);
                    disp(node);
                end
            end
            
            function drawConnection(startPt,endPt)
                if startPt(2)>endPt(2)
                    endPt_ = endPt;
                    endPt = startPt;
                    startPt = endPt_;
                end
                
                startX = startPt(1);
                startY = startPt(2) + boxSize(2)/2;
                endX = endPt(1);
                endY = endPt(2) - boxSize(2)/2;
                
                [xx,yy] = getConnectorSpline();
                
                xx = xx * (endX-startX) + startX;
                yy = yy * (endY-startY) + startY;
                
                line('Parent',hParent,'XDAta',xx,'YData',yy);
            end
            
            function w = getTreeLayoutWidth(xx,yy)
                ys = unique(yy);
                minSpacing = Inf;
                extent = 0;
                for idx_ = 1:length(ys)
                    mask = ismember(yy,ys(idx_));
                    xs = xx(mask);
                    xs = sort(xs);
                    minSpacing_ = min(diff(xs));
                    extent_ = max(xs)-min(xs);
                    if minSpacing_ < minSpacing
                        minSpacing = minSpacing_';
                        extent = extent_;
                    end
                end
                w = extent / minSpacing;
            end
        end
        
        function [parents,nodes] = getTree(obj)
            path = obj.getAncestorList();
            root = path{end};
            [parents,nodes] = getTree([0],{root});
            
            function [parents,nodes] = getTree(parents,nodes)
                nodeIdx = numel(parents);
                node = nodes{end};                
                for idx = 1:numel(node.hChildren)
                    parents(end+1) = nodeIdx; % assign parent index
                    nodes{end+1} = node.hChildren{idx}; % assign node
                    [parents, nodes] = getTree(parents,nodes);
                end
            end
        end
                
        function path = getAncestorList(obj)
            path = getAncestors(0,obj);
            
            function path = getAncestors(depth,obj)
                depth = depth+1;
                
                if isempty(obj.hParent)
                    path = cell(1,depth);
                    path{depth} = obj;
                else
                    path = getAncestors(depth,obj.hParent); % recursively traverse through tree
                    path{depth} = obj;
                end                
            end
        end
        
        function [path,toParent,commonAncestorIdx] = getRelationship(obj,other)
            % shortcut for same node for performance
            if isequal(obj,other)
                path = {obj};
                toParent = [];
                commonAncestorIdx = 1;
                return
            end
            
            assert(isscalar(other) && isa(other,obj.tnClassName) && isvalid(other));
            
            objAncestors   = obj.getAncestorList();
            otherAncestors = other.getAncestorList();
            
            if objAncestors{end} ~= otherAncestors{end}
                % no common ancestor
                path = [];
                commonAncestorIdx = [];
                return
            end
            
            minLength = min(numel(objAncestors),numel(otherAncestors));
            
            % compare ancestors
            commonAncestorIdxFromBack = 0;
            for idx = 1:(minLength-1) % don't need to compare the last ancestor, since we know it is the root of the tree
                if ~isequal( objAncestors(end-idx), otherAncestors(end-idx) )
                    break;
                else
                    commonAncestorIdxFromBack = idx;
                end
            end
            
            commonAncestor = objAncestors(end-commonAncestorIdxFromBack);
            objAncestors(end-commonAncestorIdxFromBack:end)   = [];
            otherAncestors(end-commonAncestorIdxFromBack:end) = [];
            
            path = [objAncestors commonAncestor flip(otherAncestors)];
            commonAncestorIdx = numel(objAncestors)+1;
            
            toParent = [true(1,numel(objAncestors)), false(1,numel(otherAncestors))];
        end
        
        function ancestor = getCommonAncestor(obj,other)
            [path,~,commonAncestorIdx] = obj.getRelationship(other);
            ancestor = path(commonAncestorIdx);
        end
    end
    
    %% Property Getter/Setter
    methods
        function set.hParent(obj,val)            
            if isempty(val)
                val = [];
            else
                validateattributes(val,{obj.tnClassName},{'scalar'});
                assert(isvalid(val),'Not a valid coordinate system');
            end
            
            if ~isempty(val)
                ancestorList = val.getAncestorList();
                assert(~any(cellfun(@(a)a.isequal(obj),ancestorList)),...
                    'Circular parenting is not allowed');
            end
            
            if ~isempty(val)
                obj.validateParent(val);
            end
            
            most.idioms.safeDeleteObj(obj.hParentBeingDestroyedListener);
            obj.hParentBeingDestroyedListener = [];
            if ~isempty(obj.hParent) && isvalid(obj.hParent)
                obj.hParent.removeChild(obj);
            end
            
            obj.hParent = val;
            
            if ~isempty(obj.hParent)
                obj.hParentBeingDestroyedListener = most.ErrorHandler.addCatchingListener(obj.hParent,'ObjectBeingDestroyed',@obj.parentDestroyed);
                obj.hParent.addChild(obj);
            end
            
            notify(obj,'treeChanged');
        end
    end
    
    
    %% Internal methods
    methods (Hidden)
        function parentDestroyed(obj,varargin)
            obj.hParent = [];
        end
        
        function childDestroyed(obj,src,~)
            obj.removeChild(src);
        end
    end
    
    methods (Access = protected)
        function validateParent(obj,hNewParent)
            % overload if needed
            % throws if newParent is not valid
        end
    end
        
    methods (Access = private)
        function addChild(obj,hChild)
            obj.removeChild(hChild)
            obj.hChildren{end+1} = hChild;
            obj.addChildListeners();
        end
        
        function removeChild(obj,hChild)
            tf = hChild.uuidcmp(obj.hChildren);
            obj.hChildren(tf) = [];
            obj.addChildListeners();
        end
        
        function addChildListeners(obj)
            most.idioms.safeDeleteObj(obj.hChildBeingDestroyedListeners);
            obj.hChildBeingDestroyedListeners = [];
            for idx = 1:numel(obj.hChildren)
                newListener = most.ErrorHandler.addCatchingListener(obj.hChildren{idx},'ObjectBeingDestroyed',@obj.childDestroyed);
                obj.hChildBeingDestroyedListeners = [obj.hChildBeingDestroyedListeners newListener];
            end
        end
    end
end

function [xx,yy] = getConnectorSpline()
persistent xx_ yy_
if isempty(xx_) || isempty(yy_)
    cs = spline([0 1],[0 0 1 0]);
    yy_ = linspace(0,1,100);
    xx_ = ppval(cs,yy_);
    
    straightFraction = 0.05;
    yy_ = yy_ * (1-2*straightFraction) + straightFraction;
    
    xx_ = [0 xx_ 1];
    yy_ = [0 yy_ 1];
    
end

xx = xx_;
yy = yy_;
end

%--------------------------------------------------------------------------%
% TreeNode.m                                                               %
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
