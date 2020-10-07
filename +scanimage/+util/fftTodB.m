function [dB,f] = fftTodB(fft_in,Fs,amp0)
% returns single-sided amplitude Spectrum of input signal in units of dB
%
% inputs: 
%       fft_in: raw fft of signal
%       Fs: Sampling frequency of signal
%       amp0: (optional) reference amplitude for dB calculation. default: 1
%
% returns:


if nargin < 3 || isempty(amp0)
    amp0 = 1;
end

L = numel(fft_in);  % Length of signal
P2 = abs(fft_in)/L; % normalize fft

% single sided power spectrum: double and keep only right side
amp = P2(1:floor(L/2)+1); 
amp(2:end-1) = 2*amp(2:end-1);

dB = 20 * log10(amp/amp0); % dB is defined in regards to power (reflected by factor 20)

if nargout > 1
    f = Fs*(0:(L/2))/L;
end

end

%--------------------------------------------------------------------------%
% fftTodB.m                                                                %
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
