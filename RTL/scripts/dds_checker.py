import peakutils
import numpy as np
import math
import os
import matplotlib.pyplot as plot


class dds_checker:
    """ 
    This class implements verification routines for the DDS Generator test bench
    
    It performs fourier anlysis of the generated waveforms and reports various signal parameters.
    The following parameters are calculated from the generated waveform:
        - Carrier frequency, amplitude and phase
        - Biggest harmonic frequency, amplitude
        - Spurious free dynamic range
        - Total harmonic distortion
        
    For most of these parameters center values and tollerance can be specified that will be verified.
    """
        
    config : dict = None
    
    output_path : str = None
    
    def __init__(self, config : dict):
        self.config = config


    def __analyse_spectrum(self, carrier : list[float], name) -> bool:
        """Performs FFT analysis of the provided carrier signal and reports the calculated parameters."""
        
        # calculate FFT for carrier
        spectrum_complex = np.fft.rfft(carrier) / len(carrier) * 2
        spectrum = 20*np.log10( np.abs( spectrum_complex ) )
        freq     = np.fft.rfftfreq(len(carrier), d=10e-9)
    
        # find peaks
        peaks = peakutils.indexes(spectrum, 0.3)
        ampls = spectrum[peaks]
        freqs = freq[peaks]
        complx = spectrum_complex[peaks]
        
        # sort haromics by amplitude
        arr_sort_idx = ampls.argsort()
        ampls_sorted = ampls[arr_sort_idx[::-1]]
        freqs_sorted = freqs[arr_sort_idx[::-1]]
        complx_sorted = complx[arr_sort_idx[::-1]]
        
        # calculate total harmonic distortion
        sum_harmonics = sum( np.power(10, ampls_sorted[1::] / 10) )
        THD = np.sqrt(sum_harmonics) / np.power(10, ampls_sorted[0] / 20)
    
        # generate image
        fig, ax = plot.subplots(1,1, figsize=(10,10))
        ax.plot(freq/1e6, spectrum);
        ax.set_xlabel("f / MHz")
        ax.set_ylabel("A / dbFS")        
        ax.set_ylim([-120, 0])
        ax.grid(True, "both")
        
        # save
        fig.tight_layout()
        fig.savefig(os.path.join(self.output_path, f"spectrum_{name}.png"))
        
        # return result
        result = {
            "center": {
                "freq": freqs_sorted[0],
                "ampl": ampls_sorted[0],
                "phase": np.angle( complx_sorted[0] )
            },
            "biggest_harmonic": {
                "freq": freqs_sorted[1] if len(freqs_sorted) > 1 else 0,
                "ampl": ampls_sorted[1] if len(ampls_sorted) > 1 else 0
            },
            "SFDR": (ampls_sorted[0] - ampls_sorted[1]) if len(ampls_sorted) > 1 else 0,
            "THD" : THD
        }
        return result       

    def __verify_spectrum(self, name : str, result : dict) -> bool:
        """Verifies that the provided parameters (as retrieved via __analyse_spectrun() are within the boundaries specified during instance creation. """
        
        print(f"\nResults for carrier: '{name}'")   
        
        does_pass = True
        
        # verify frequency error
        freq_error = result["center"]["freq"] - self.config["target_frequency"];
        target_freq = self.config["target_frequency"] / 1e6
        print(f"\tFrequency Error: {round(freq_error):.0f} Hz (Target: {target_freq:.3f} MHz)" )
        
        if abs(freq_error) > self.config["target_frequency_tollerance"]:
            print("\t\tFAILED")
            does_pass = False
        else:
            print("\t\tOK")
            
        ampl_error = result["center"]["ampl"]
        print(f"\tAmplitude Error: {ampl_error:.3f} dBFS (Target: 0.000 dBFS)" )
        if abs(ampl_error) > self.config["amplitude_tollerance"]:
            print("\t\tFAILED")
            does_pass = False
        else:
            print("\t\tOK")
            
        SFDR = result["SFDR"]
        print(f"\tSFDR: {SFDR:.2f} dBc")
        if SFDR < self.config["SFDR_min"]:
            print("\t\tFAILED")
            does_pass = False
        else:
            print("\t\tOK")
            
        return does_pass

    def __verify_carrier_relations(self, result_cos : dict, result_sin : dict) -> bool:
        """Verifies the relation between both generated carrier signals."""
        does_pass = True
        
        phase_difference = math.remainder(result_cos["center"]["phase"] - result_sin["center"]["phase"], 2*math.pi)
        phase_difference = (phase_difference / math.pi) * 180
        expected_phase = self.config["expected_phase"]
        
        print("\nCarrier comparison:")
        print(f"\tPhase (cos-sin): {phase_difference:.2f} degrees (Target: {expected_phase:.2f} degrees)")
        if abs(expected_phase - phase_difference) > self.config["expected_phase_tollerance"]:
            print("\t\tFAILED")
            does_pass = False
        else:
            print("\t\tOK")
        
        return does_pass

    def  post_check(self, output_path) -> bool:
        """
        Check function that reads the waveforms from the testbench output file. Analyses them and checks the configured parameters.
        If a check failes then this method returns false.
        """
        
        self.output_path = output_path
        
        # get carrier from file
        carrier_cos, carrier_sin = np.genfromtxt(f"{output_path}/carrier.txt", encoding="utf8", unpack=True)
        
        # normalize to range [1, -1]
        carrier_cos = carrier_cos / np.power(2, 15)
        carrier_sin = carrier_sin / np.power(2, 15)
        
        result_cos = self.__analyse_spectrum(carrier_cos, "cos")
        result_sin = self.__analyse_spectrum(carrier_sin, "sin")        
        cos_pass = self.__verify_spectrum("cos", result_cos)
        sin_pass = self.__verify_spectrum("sin", result_sin)

        relations_pass = self.__verify_carrier_relations(result_cos, result_sin)

        return cos_pass and sin_pass and relations_pass
    