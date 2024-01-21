SAMPLES = 10e3;

CARRIER_OFFSET = 41;

FS = 100e6;
MAX_VALUE = 20000;


IQ = [1+1j; -1-1j];

modulator_data = repelem(IQ', SAMPLES/length(IQ));

frequency = 5.0e6 + 50e3;

time = 0:1:SAMPLES-1;
time = 1/FS * time;

carrier_sin = -sin(2*pi*frequency*time + deg2rad(CARRIER_OFFSET));
carrier_cos = cos(2*pi*frequency*time  + deg2rad(CARRIER_OFFSET));

data = (carrier_cos .* real(modulator_data) + carrier_sin .* imag(modulator_data));
data = awgn(data, 20, 0);
data = (data / sqrt(2)) * MAX_VALUE;

file = fopen("iq_data.txt", "w");
for i = 0:1:SAMPLES-1
    fprintf(file, "%i\n", int16(data(i + 1)));
end

fclose(file);
