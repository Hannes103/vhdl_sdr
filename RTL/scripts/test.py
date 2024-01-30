import iq_checker

cfg = {
    "samples": 2e3,
    "freq": 100e3,
    "ampl": 0.4,
    "SNR": 3,

    "data": [1+1j]
}

checker = iq_checker.iq_checker(cfg)
checker.pre_config(".")