function valid = str2validName(propname, prefix)
% CONVERT2VALIDNAME
% Converts the property name into a valid matlab property name.
% propname: the offending propery name
% prefix: optional prefix to use instead of the ambiguous "dyn"
valid = propname;
if isvarname(valid) && ~iskeyword(valid)
    return;
end

if nargin < 2 || isempty(prefix)
    prefix = 'dyn_';
else
    if ~isvarname(prefix)
        warning('Prefix contains invalid variable characters.  Reverting to "dyn"');
        prefix = 'dyn_';
    end
end

% general regex /[a-zA-Z]\w*/

%find all alphanumeric and '_' characters
valididx = isstrprop(valid, 'alphanum');
valididx(strfind(valid, '_')) = true;

% replace all invalid characters with '_' for now
valid(~valididx) = '_';

if isempty(valid) || ~isstrprop(valid(1), 'alpha') || iskeyword(valid)
    valid = [prefix valid];
end
end

%--------------------------------------------------------------------------%
% str2validName.m                                                          %
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
