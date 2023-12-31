FS = 100e6;

MAX_VALUE = 2^15;

result = readtable("carrier.txt");
result.Properties.VariableNames = {'cos', 'sin'};

result.cos = result.cos / MAX_VALUE;
result.sin = result.sin / MAX_VALUE;

% spectrum
pspectrum(result.cos, FS)


plot(result.cos);
ylim([-1.1, 1.1]);