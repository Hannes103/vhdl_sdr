% order of CIC filter
ORDER = 8;
% decimation factor
DECIMATION = 8;
FIR_DECIMATION = 4;
% number of bits in the input
INPUT_WIDTH = 8;
INPUT_FRACTION_BITS = 3;

LENGTH = 5*DECIMATION;

F_SAMPLE = 100e6;
F_CIC    = F_SAMPLE / DECIMATION;

% create CIC decimator from order and decimation factor 

cic = dsp.CICDecimator(DECIMATION, 1, ORDER);
cic.FixedPointDataType = "Specify word and fraction lengths";
cic.OutputWordLength = INPUT_FRACTION_BITS + INPUT_WIDTH + ceil(ORDER * log2(DECIMATION));
cic.OutputFractionLength = INPUT_FRACTION_BITS;
cic.SectionWordLengths = INPUT_FRACTION_BITS + INPUT_WIDTH + ceil(ORDER * log2(DECIMATION));
cic.SectionFractionLengths = INPUT_FRACTION_BITS;

% prepare input signal
time = [0:LENGTH-1];
signal = time *0 + 100.5;

signal = transpose(fi(signal, true, INPUT_WIDTH+INPUT_FRACTION_BITS,INPUT_FRACTION_BITS));

source = dsp.SignalSource(signal, length(signal));

% filter and normalize by gain
filtered = double(cic(source())) / DECIMATION^ORDER;

hold on;
stem([0:1:LENGTH-1], signal, 'b');
stem([0:DECIMATION:LENGTH-1], filtered, 'r', 'filled');

ylim([-128, 127]);
grid minor;

% cic compensation filter
cic_comp_design = fdesign.ciccomp(1, ORDER, DECIMATION, 'n,fp,fst', 63, 1/FIR_DECIMATION, 1.5/FIR_DECIMATION);
fir_comp = design(cic_comp_design, 'SystemObject', true);

fv = fvtool(cascade(cic,1/gain(cic)),cascade(cic,1/gain(cic), fir_comp));
fv.ShowReference = 'off';
fv.NormalizedFrequency = 'off';
fv.Fs = 100e6;
legend(fv, "CIC", "CIC + FIR");
