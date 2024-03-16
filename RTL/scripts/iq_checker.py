import numpy as np
import math
import os

import matplotlib.pyplot as plot

class iq_checker:
  
    SAMPLING_FREQ = 100e6
  
    config : dict = None
    showGraph : bool = None
    
    def __init__(self, config : dict, showGraph : bool = False):
        self.config = config
        self.showGraph = showGraph
    
    def __generate_data(self) -> list[float]:
        # generate carrier samples at specified frequency
        t = np.linspace(0, self.config["samples"] - 1, int(self.config["samples"]))
        carrier_sin = -np.sin(t/self.SAMPLING_FREQ * 2*np.pi * self.config["freq"])
        carrier_cos =  np.cos(t/self.SAMPLING_FREQ * 2*np.pi * self.config["freq"])
    
        # repeat input data to fit the entire carrier length
        data_repeat_count = len(t) / len(self.config["data"])
        data = np.repeat(self.config["data"], data_repeat_count)
        
        # module data and return result
        result = (np.multiply( carrier_cos, np.real(data) ) + np.multiply(carrier_sin, np.imag(data))) / np.sqrt(2)
        
        SNR = np.power(10, -self.config["SNR"] / 10)
        
        noise = np.random.normal(0,SNR,len(t))
        
        result_with_noise = np.clip( self.config["offset"] + (result + noise) * self.config["ampl"], -1, 1)
        return result_with_noise
    
    def pre_config(self, output_path : str) -> bool:     
        data = math.pow(2, 15) * self.__generate_data()
        
        np.savetxt(os.path.join(output_path, "input.txt"), data, delimiter="\t", fmt="%d")
        return True
    
    def __color_y_axis(self, ax, color):
        """Color your axes."""
        for t in ax.get_yticklabels():
            t.set_color(color)
        return None
    
    def post_check(self, output_path) -> bool:
        # read baseband signal from output file
        input = np.genfromtxt(f"{output_path}/baseband.txt", encoding="utf8")
        
        baseband_i = input[:,0]
        baseband_q = input[:,1]    
            
        # calculate amplitude and phase information
        time = [float(x)*0.32 for x in range(0, len(baseband_i))] # 0.01 us/clock * 32 clocks/sample
        ampl  = np.sqrt( np.square(baseband_i) + np.square(baseband_q) )
        phase = np.rad2deg(np.arctan2( baseband_i, baseband_q ))
        
        if len(input[0]) == 3:
            nco_adj = input[:,2]
            
            fig, (ax1, ax2, ax3) = plot.subplots(3,1, figsize=(10,15))
            
            ax3.plot(time, nco_adj)
            ax3.set_title("NCO adjustment for carrier recovery") 
            ax3.set_ylim([-0.3, 0.3])
            ax3.set_xlabel("t / us", loc='right')
            ax3.set_ylabel(r"relative frequency adj. / $\frac{f_{carrier}}{f_{adc}}$")
            ax3.grid(True, "both")
        else:
            fig, (ax1, ax2) = plot.subplots(2,1, figsize=(10,10))
        
        # plot baseband signal
        ax1.set_title("Baseband (I/Q)")
        ax1.plot(time, baseband_i)
        ax1.plot(time, baseband_q)
        ax1.legend(["I", "Q"])
        ax1.set_xlabel("t / us", loc='right')
        ax1.grid(True, "both")

        # plot amplitude and phase
        ax2.set_title("Baseband (Amplitude/Phase)")
        ax2.plot(time, ampl)
        ax2.set_ylabel("Ampltiude")
        ax2.set_xlabel("t / us", loc='right')
        
        # second subplot has a second axis that display the phase in 45° increments
        ax2a = ax2.twinx()
        ax2a.plot(time, phase, color="tab:orange")
        ax2a.set_ylim([-180, 180])
        ax2a.set_ylabel("Phase / deg")
        ax2a.yaxis.set_ticks([-180, -135, -90, -45, 0, 45, 90, 135, 180])
        ax2a.grid(True, "both")
    
        self.__color_y_axis(ax2a, "tab:orange")

        # save to file and show in interactive window if requested
        fig.savefig(os.path.join(output_path, "baseband.png"))
        if self.showGraph:
            fig.show()
            plot.show()
        
        return True