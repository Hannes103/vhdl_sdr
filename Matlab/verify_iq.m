FS = 100e6/8;

MAX_VALUE = 2^15;

THRESHOLD = 3500;

result = readtable("result.txt");
result.Properties.VariableNames = {'I', 'Q', 'error'};

time = 0:1:length(result.I)-1;
time = 1/FS * time;

IQ = result.I + 1j * result.Q;

zero_idx = find(abs(IQ) < THRESHOLD);

ampl = abs(IQ);
phase = angle(IQ);
phase(zero_idx) = 0;
% phase = unwrap(phase);

close;
subplot(2,1,1);
plot(time, ampl);

subplot(2,1,2);
plot(time, rad2deg(phase));

xlim([0, 10e-5]);

%scatter(real(IQ), imag(IQ));