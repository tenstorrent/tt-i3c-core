// SPDX-License-Identifier: Apache-2.0
// Derived from the CHIPS Alliance I3C UVM VIP and vendored through
// the Tenstorrent tt-i3c-core fork.

`include "i3c_direct_data_seq.sv"
`include "i3c_direct_data_with_rstart_seq.sv"
`include "i3c_broadcast_followed_by_data_seq.sv"
`include "i3c_broadcast_followed_by_data_with_rstart_seq.sv"
`include "i2c_direct_data_seq.sv"
`include "i2c_direct_data_with_rstart_seq.sv"
`include "i3c_broadcast_followed_by_i2c_data_seq.sv"
`include "i3c_broadcast_followed_by_i2c_data_with_rstart_seq.sv"
