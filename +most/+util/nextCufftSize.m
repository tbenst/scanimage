function [A,optimizedPrimes,powers] = nextCufftSize(A,direction,evenflag)
    % cufft is fastest for input sizes that can be written in the form
    % 2^a * 3^b * 5^c * 7^d . In general the smaller the prime factor, the
    % better the performance, i.e., powers of two are fastest.
    % https://docs.nvidia.com/cuda/cufft/index.html
    
    if nargin < 2 || isempty(direction)
        direction = 1;
    end
    
    even = false;
    odd  = false;
    
    if nargin >= 3 && ~isempty(evenflag)
        switch lower(evenflag)
            case 'even'
                even = true;
            case 'odd'
                odd = true;
            otherwise
                error('Unknown flag: %s',evenflag);
        end
    end
    
    direction = sign(direction);
    optimizedPrimes = [2 3 5 7];
    
    nextpowprimes_fun = @most.util.nextpowprimes;
    
    if ~verLessThan('matlab','9.2')
        % memoize for performance in Matlab 2017a or later
        nextpowprimes_fun = memoize(nextpowprimes_fun);
    end
    
    [powers,A] = nextpowprimes_fun(A, optimizedPrimes, direction);
    
    if ( odd && mod(A,2)==0 ) || ( even && mod(A,2)==1 )
        [powers,A] = nextpowprimes_fun(A + 1 * direction, optimizedPrimes, direction);
    end
end



%--------------------------------------------------------------------------%
% nextCufftSize.m                                                          %
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
