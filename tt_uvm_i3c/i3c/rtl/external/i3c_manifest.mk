# Pinned upstream sources used by the OCAH SMC I3C integration.
I3C_SOURCE_PINS     := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../sim/project/i3c_source_pins.mk)
include $(I3C_SOURCE_PINS)

I3C_CONFIG          := tt-axi-controller
I3C_TOP             := i3c_wrapper
I3C_MIN_VCS_VERSION := 2020.12
I3C_WINDOW_BYTES    := 4096
