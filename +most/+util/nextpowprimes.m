function [P,A] = nextpowprimes(A,primes,direction)
    % like nextpow2, but allows to specify the prime factors
    if nargin<3 || isempty(direction)
        direction = 1;
    end
    
    validateattributes(A,{'numeric'},{'positive','integer','real'},'Input A needs to be a positive integer');
    validateattributes(primes,{'numeric'},{'>=',2,'integer','increasing','vector','real'},'primes input vector needs to be sorted prime numbers');
    assert(all(isprime(primes)),'primes input vector needs to be prime');
    validateattributes(direction,{'numeric','logical'},{'scalar','nonnan','real'},'Direction needs to be -1 OR 1 OR true OR false');
    
    P = zeros(size(primes),'like',primes);
    if A == 1
        return;
    end
    
    if direction > 0
        increment = 1;
    else
        increment = -1;
    end
    
    while true
        factors = factor(A);
        undesired_factors = setdiff(factors,primes);
        if isempty(undesired_factors)
            break % found a match
        else
            A = A+increment;
        end
    end
    
    for idx = 1:numel(primes)
        P(idx) = sum(factors == primes(idx));
    end
end

%--------------------------------------------------------------------------%
% nextpowprimes.m                                                          %
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
