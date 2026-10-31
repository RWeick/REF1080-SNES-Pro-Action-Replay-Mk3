// LZ95G72 behavioral model
//
module lz95g72 (
    input  logic        pwr_good,             // pin 8; low is the ASIC reset
    input  logic        middle_slot_insert_n, // pin 1; external pull-up, low=cart
    input  logic        ff_reset_n,            // pin 5; with pin 4 low clears Control B
    input  logic        switch_menu_n,         // pin 4; low = bottom/menu position
    input  logic        switch_active_n,       // pin 6; low = top/fully-active position
    input  logic        read_sys_n,            // pin 7
    input  logic        write_n,               // pin 45
    input  logic        test_strap_46,         // pin 46; tie low as on REF1080
    input  logic [15:0] address,
    input  logic [7:0]  bank,
    input  logic [7:0]  data_in,

    output logic [7:0]  data_out,
    output logic        data_oe,
    output logic        middle_cart_select,    // pin 2; inverse of pin 1
    output logic        sram_ce_n,             // pin 48
    output logic        read_top_n,            // pin 49
    output logic        eprom_oe_n,            // pin 50
    output logic        hidden_51_n,            // pin 51; complementary ROM-bank read
    output logic        led_en_n,              // pin 52
    output logic        write_internal_n,      // pin 53
    output logic        aux_54,                 // pin 54; pin63 OR NOT(ControlA[2])
    output logic        hidden_55_n,            // pin 55
    output logic        d4_pulldown,           // pin 56; active high
    output logic        hidden_59_n,            // pin 59
    output logic        d4_pullup_n,           // pin 60; active low
    output logic        game_latch,            // pin 61; Control-B mirror
    output logic        compare_match,         // pin 62; includes detect-only slot 7
    input  logic        aux_input_63,           // pin 63; follows external bias
    input  logic        aux_input_64,           // pin 64; selects pin-55 polarity

    output logic [7:0]  control_a_debug,
    output logic        control_c_debug
);

  logic [7:0]  slot_data [0:6];
  logic [23:0] slot_addr [0:7];
  logic [7:0]  control_a;
  logic        control_b;
  logic        control_c;
  logic [7:0]  match;
  logic        compare_enable;
  logic        sram_window;
  logic        bios_bank;
  logic        top_read_path;
  logic        region_read;
  logic        write_inhibit;
  logic        control_c_window;
  logic        menu_reset_n;
  integer reset_index;
  integer compare_index;

  always_ff @(negedge write_n or negedge pwr_good) begin
    if (!pwr_good) begin
      control_a <= 8'h00;
      for (reset_index = 0; reset_index < 7; reset_index = reset_index + 1) begin
        slot_data[reset_index] <= 8'h00;
        slot_addr[reset_index] <= 24'h000000;
      end
      slot_addr[7] <= 24'h000000;
    end else if ((bank == 8'h10) && !control_b) begin
      if (address[4:0] <= 5'h1B) begin
        case (address[1:0])
          2'd0: slot_data[address[4:2]]       <= data_in;
          2'd1: slot_addr[address[4:2]][7:0]  <= data_in;
          2'd2: slot_addr[address[4:2]][15:8] <= data_in;
          2'd3: slot_addr[address[4:2]][23:16] <= data_in;
        endcase
      end

      if (address[4:0] == 5'h1D)
        slot_addr[7][7:0] <= data_in;
      if (address[4:0] == 5'h1E)
        slot_addr[7][15:8] <= data_in;
      if (address[4:0] == 5'h1F)
        slot_addr[7][23:16] <= data_in;
      if (address[5:0] == 6'h1C) begin
        if (control_c)
          control_a <= {data_in[7:1], control_a[0]};
        else
          control_a <= data_in;
      end
    end
  end

  always_ff @(negedge write_n or negedge pwr_good) begin
    if (!pwr_good)
      control_c <= 1'b0;
    else if ((address[15:13] == 3'b011) && (bank[7:3] == 5'b00100))
      control_c <= data_in[0];
  end

  assign menu_reset_n = ff_reset_n | switch_menu_n;
  always_ff @(negedge write_n or negedge pwr_good or negedge menu_reset_n) begin
    if (!pwr_good || !menu_reset_n)
      control_b <= 1'b0;
    else if ((bank == 8'h10) && (address[5:0] == 6'h3C))
      control_b <= 1'b1;
  end

  always_comb begin
    compare_enable = pwr_good && control_b && !switch_active_n
                   && !control_a[4];
    for (compare_index = 0; compare_index < 8; compare_index = compare_index + 1)
      match[compare_index] = ({bank, address} == slot_addr[compare_index]);

    data_out = 8'h00;
    for (compare_index = 0; compare_index < 7; compare_index = compare_index + 1)
      if (match[compare_index]) data_out = data_out | slot_data[compare_index];
    data_oe       = compare_enable && !read_sys_n && (|match[6:0]);
    compare_match = |match;

    sram_window = (address[15:13] == 3'b011) && (bank[7:5] == 3'b000);
    sram_ce_n    = !(sram_window && !bank[3]);
    led_en_n     = !(sram_window &&  bank[3]);

    control_c_window = (address[15:13] == 3'b011)
                     && (bank[7:3] == 5'b00100);
    write_inhibit = (control_c_window ? data_in[0] : control_c)
                  && !control_a[0];
    write_internal_n = write_n || write_inhibit;

    bios_bank    = (bank[7:4] == 4'h0) && !bank[2];
    top_read_path = control_b ^ control_a[4];
    read_top_n    = read_sys_n || !top_read_path
                  || (compare_enable && (|match[6:0]));
    eprom_oe_n    = read_sys_n || !bios_bank || top_read_path;
    hidden_51_n   = read_sys_n || (bank[7:4] != 4'h0) || !bank[2]
                  || top_read_path;

    region_read  = (address == 16'h213F) && !bank[6];
    d4_pulldown  = control_a[6] && region_read;
    d4_pullup_n  = !(control_a[7] && region_read);

    hidden_55_n  = !(control_a[3] && !(control_a[5] ^ aux_input_64));
    hidden_59_n  = !(control_b && (control_a[1] ^ match[7]));
    game_latch   = control_b;
    aux_54         = aux_input_63 || !control_a[2];

    middle_cart_select = !middle_slot_insert_n;
    control_a_debug = control_a;
    control_c_debug = control_c;
  end

endmodule
