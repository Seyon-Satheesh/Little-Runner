/*
 * Tiny Runner
 * 
 * A game where you run forever and avoid objects.
 * Keep your tiny runner alive for as long as possible.
 */

`default_nettype none

module tt_um_vga_example(
  input  wire [7:0] ui_in,    // Dedicated inputs
  output wire [7:0] uo_out,   // Dedicated outputs
  input  wire [7:0] uio_in,   // IOs: Input path
  output wire [7:0] uio_out,  // IOs: Output path
  output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
  input  wire       ena,      // always 1 when the design is powered, so you can ignore it
  input  wire       clk,      // clock
  input  wire       rst_n     // reset_n - low to reset
);

  // VGA signals
  wire hsync;
  wire vsync;
  reg [1:0] R;
  reg [1:0] G;
  reg [1:0] B;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;
  reg sound;

  // TinyVGA PMOD
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
  assign uio_out = {sound, 7'b0};

  // Unused outputs assigned to 0.
  assign uio_oe  = 8'hff; // This line was the solution to audio issue

  // Suppress unused signals warning
  wire _unused_ok = &{ena, ui_in, uio_in};

  // Instantiate the HSync/VSync generator
  hvsync_generator hvsync_gen(
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(video_active),
    .hpos(pix_x),
    .vpos(pix_y)
  );

  // Gamepad Pmod
  wire inp_b, inp_y, inp_select, inp_start, inp_up, inp_down, inp_left, inp_right, inp_a, inp_x, inp_l, inp_r;

  gamepad_pmod_single driver (
      // Inputs:
      .rst_n(rst_n),
      .clk(clk),
      .pmod_data(ui_in[6]),
      .pmod_clk(ui_in[5]),
      .pmod_latch(ui_in[4]),
      // Outputs:
      .b(inp_b),
      .y(inp_y),
      .select(inp_select),
      .start(inp_start),
      .up(inp_up),
      .down(inp_down),
      .left(inp_left),
      .right(inp_right),
      .a(inp_a),
      .x(inp_x),
      .l(inp_l),
      .r(inp_r)
  );

  // GAME LOGIC

  // Constants
  localparam [5:0] BACKGROUND_COLOR = {2'b01, 2'b10, 2'b11};
  localparam [5:0] GROUND_COLOR = {2'b01, 2'b11, 2'b10};
  localparam [5:0] DIRT_COLOR = {2'b10, 2'b01, 2'b01};

  localparam [5:0] PLAYER_BRIGHT_COLOR = {2'b10, 2'b01, 2'b10};
  localparam [5:0] PLAYER_DARK_COLOR = {2'b01, 2'b10, 2'b10};

  localparam [31:0] HIGH_BEEP_FREQUENCY = 32'd50000;
  localparam [31:0] LOW_BEEP_FREQUENCY = 32'd500000;

  localparam [9:0] GROUND_Y = 10'd400;
  localparam [9:0] DIRT_Y = 10'd410;

  localparam [9:0] GRAVITY_ACCELERATION = 10'd10;
  localparam [9:0] JUMP_SPEED = 10'd50;

  localparam [9:0] SCROLL_SPEED = 10'd20;

  localparam [9:0] PLAYER_WIDTH = 10'd50;
  localparam [9:0] PLAYER_HEIGHT = 10'd100;

  localparam [9:0] STARTING_X = 10'd100;
  localparam [9:0] STARTING_Y = GROUND_Y - PLAYER_HEIGHT[9:1];

  // Player values
  reg [9:0] player_x = STARTING_X;
  reg [9:0] player_y = STARTING_Y;

  reg signed [9:0] player_y_speed = 0;
  reg signed [9:0] player_y_acceleration = $signed(GRAVITY_ACCELERATION);

  reg [2:0] player_position = 0; // 0 - Normal, 1 - Jump, 2 - Crouch
  reg [7:0] player_keyframe = 0;

  wire signed [9:0] player_next_speed_clone;
  assign player_next_speed_clone = player_y_speed + player_y_acceleration;

  // Attack values


  // Audio logic
  reg [31:0] sound_counter = 0;
  reg [31:0] current_frequency = HIGH_BEEP_FREQUENCY;
  reg play_sound = 0;

  always @(posedge clk) begin
    if (play_sound) begin
      if (sound_counter > current_frequency) begin
        sound <= ~sound;
        sound_counter <= 0;
      end else begin
        sound_counter <= sound_counter + 1;
      end
    end else begin
      sound <= 0;
      sound_counter <= 0;
    end
  end

  // Temp values
  reg [9:0] temp_x = 0;
  reg [9:0] temp_y = 0;
  
  // Game loop
  always @(posedge clk) begin
    if (~rst_n) begin
      // Reset values if reset button pressed
      R <= 0;
      G <= 0;
      B <= 0;
      player_x <= STARTING_X;
      player_y <= STARTING_Y;
      player_y_speed <= 0;
      player_y_acceleration <= $signed(GRAVITY_ACCELERATION);
      player_position <= 0;
      player_keyframe <= 0;
      sound_counter <= 0;
      play_sound <= 0;
      current_frequency <= HIGH_BEEP_FREQUENCY;
      temp_x <= 0;
      temp_y <= 0;
    end else begin
      if (video_active) begin
        // If pixel is visible, run game code

        // Run once a frame
        if (pix_x == 0 && pix_y == 0) begin
          player_keyframe <= player_keyframe + 1;
          // player_keyframe <= 3;

          if (inp_up && player_position == 0) begin
            player_y_speed <= -$signed(JUMP_SPEED);
            // player_y_speed <= -10'sd1;
            player_position <= 1;
            player_keyframe <= 0;
          end

          // {player_y_speed, player_y} <= {{player_y_speed + player_y_acceleration}, {player_y + player_y_speed}};

          // player_y_speed <= player_y_speed + player_y_acceleration;
          // player_y <= player_y + player_y_speed;
          // player_y_speed <= player_y_speed;
          player_y <= player_y + player_y_speed;

          if (player_position == 1) begin
            player_y_speed <= player_y_speed + player_y_acceleration;
          end
          // player_y_speed <= player_next_speed_clone;
          // player_y_speed <= player_next_speed_clone;
          // player_y <= player_y_acceleration+50;

          if ((player_y + PLAYER_HEIGHT[9:1]) > GROUND_Y) begin
            player_y <= GROUND_Y - PLAYER_HEIGHT[9:1];
            player_y_speed <= 0;
            player_position <= 0;
            player_keyframe <= 0;
          end

          if (player_position == 0 && player_keyframe >= 10) begin
            player_keyframe <= 0;
          end else if (player_position == 2 && player_keyframe >= 20) begin
            player_position <= 0;
            player_keyframe <= 0;
          end
        end

        // Run once per pixel per frame
        if (pix_y > DIRT_Y) begin
          // If pixel is below grass, display color of dirt
          R <= DIRT_COLOR[5:4];
          G <= DIRT_COLOR[3:2];
          B <= DIRT_COLOR[1:0];
        end else if (pix_y > GROUND_Y) begin
          // If pixel is in grass range, display color of grass
          R <= GROUND_COLOR[5:4];
          G <= GROUND_COLOR[3:2];
          B <= GROUND_COLOR[1:0];
        end else begin
          if (pix_x >= (player_x - PLAYER_WIDTH[9:1]) && pix_x <= (player_x + PLAYER_WIDTH[9:1]) && pix_y >= (player_y - PLAYER_HEIGHT[9:1]) && pix_y <= (player_y + PLAYER_HEIGHT[9:1])) begin
            temp_x <= pix_x - player_x + PLAYER_WIDTH[9:1];
            temp_y <= pix_y - player_y + PLAYER_HEIGHT[9:1];

            if (player_position == 0) begin
              if (player_keyframe < 5) begin
                if (temp_x >= 10 && temp_x <= 40 && temp_y <= 30) begin
                  R <= PLAYER_BRIGHT_COLOR[5:4];
                  G <= PLAYER_BRIGHT_COLOR[3:2];
                  B <= PLAYER_BRIGHT_COLOR[1:0];
                end else if (temp_x >= 20 && temp_x <= 30 && temp_y > 30 && temp_y <= 40) begin
                  R <= PLAYER_BRIGHT_COLOR[5:4];
                  G <= PLAYER_BRIGHT_COLOR[3:2];
                  B <= PLAYER_BRIGHT_COLOR[1:0];
                end else if (temp_x >= 15 && temp_x <= 35 && temp_y > 40 && temp_y <= 70) begin
                  R <= PLAYER_BRIGHT_COLOR[5:4];
                  G <= PLAYER_BRIGHT_COLOR[3:2];
                  B <= PLAYER_BRIGHT_COLOR[1:0];
                end else if (temp_x >= 35 && temp_x <= 45 && temp_y > 60) begin
                  R <= PLAYER_BRIGHT_COLOR[5:4];
                  G <= PLAYER_BRIGHT_COLOR[3:2];
                  B <= PLAYER_BRIGHT_COLOR[1:0];
                end else if (temp_x >= 10 && temp_x <= 20 && temp_y > 60 && temp_y < 90) begin
                  R <= PLAYER_BRIGHT_COLOR[5:4];
                  G <= PLAYER_BRIGHT_COLOR[3:2];
                  B <= PLAYER_BRIGHT_COLOR[1:0];
                end else if (temp_x >= 0 && temp_x <= 10 && temp_y > 75 && temp_y < 90) begin
                  R <= PLAYER_BRIGHT_COLOR[5:4];
                  G <= PLAYER_BRIGHT_COLOR[3:2];
                  B <= PLAYER_BRIGHT_COLOR[1:0];
                end else begin
                  // R <= 3;
                  // G <= 0;
                  // B <= 0;
                  R <= BACKGROUND_COLOR[5:4];
                  G <= BACKGROUND_COLOR[3:2];
                  B <= BACKGROUND_COLOR[1:0];
                end
              end else begin
                if (temp_x >= 10 && temp_x <= 40 && temp_y <= 40 && temp_y >= 10) begin
                  R <= PLAYER_BRIGHT_COLOR[5:4];
                  G <= PLAYER_BRIGHT_COLOR[3:2];
                  B <= PLAYER_BRIGHT_COLOR[1:0];
                end else if (temp_x >= 20 && temp_x <= 30 && temp_y > 40 && temp_y <= 50) begin
                  R <= PLAYER_BRIGHT_COLOR[5:4];
                  G <= PLAYER_BRIGHT_COLOR[3:2];
                  B <= PLAYER_BRIGHT_COLOR[1:0];
                end else if (temp_x >= 15 && temp_x <= 35 && temp_y > 50 && temp_y <= 70) begin
                  R <= PLAYER_BRIGHT_COLOR[5:4];
                  G <= PLAYER_BRIGHT_COLOR[3:2];
                  B <= PLAYER_BRIGHT_COLOR[1:0];
                end else if (temp_x >= 15 && temp_x < 25 && temp_y > 60) begin
                  R <= PLAYER_BRIGHT_COLOR[5:4];
                  G <= PLAYER_BRIGHT_COLOR[3:2];
                  B <= PLAYER_BRIGHT_COLOR[1:0];
                end else if (temp_x > 25 && temp_x <= 35 && temp_y > 60) begin
                  R <= PLAYER_BRIGHT_COLOR[5:4];
                  G <= PLAYER_BRIGHT_COLOR[3:2];
                  B <= PLAYER_BRIGHT_COLOR[1:0];
                end else if (temp_x >= 5 && temp_x <= 15 && temp_y > 90) begin
                  R <= PLAYER_BRIGHT_COLOR[5:4];
                  G <= PLAYER_BRIGHT_COLOR[3:2];
                  B <= PLAYER_BRIGHT_COLOR[1:0];
                // end else if (temp_x >= 15 && temp_x <= 25 && temp_y > 60 && temp_y < 90) begin
                //   R <= PLAYER_BRIGHT_COLOR[5:4];
                //   G <= PLAYER_BRIGHT_COLOR[3:2];
                //   B <= PLAYER_BRIGHT_COLOR[1:0];
                // end else if (temp_x >= 5 && temp_x <= 15 && temp_y > 75 && temp_y < 90) begin
                //   R <= PLAYER_BRIGHT_COLOR[5:4];
                //   G <= PLAYER_BRIGHT_COLOR[3:2];
                //   B <= PLAYER_BRIGHT_COLOR[1:0];
                end else begin
                  // R <= 3;
                  // G <= 0;
                  // B <= 0;
                  R <= BACKGROUND_COLOR[5:4];
                  G <= BACKGROUND_COLOR[3:2];
                  B <= BACKGROUND_COLOR[1:0];
                end
              end
            end else begin
              R <= PLAYER_BRIGHT_COLOR[5:4];
              G <= PLAYER_BRIGHT_COLOR[3:2];
              B <= PLAYER_BRIGHT_COLOR[1:0];
            end
          end else begin
            R <= BACKGROUND_COLOR[5:4];
            G <= BACKGROUND_COLOR[3:2];
            B <= BACKGROUND_COLOR[1:0];
          end
        end
      end else begin
        // If pixel not on screen, display plain black
        R <= 0;
        G <= 0;
        B <= 0;
      end
    end
  end

endmodule

/*
 * Copyright (c) 2025 Pat Deegan, https://psychogenic.com
 * SPDX-License-Identifier: Apache-2.0
 * Version: 1.0.0
 *
 * Interfacing code for the Gamepad Pmod from Psycogenic Technologies,
 * designed for Tiny Tapeout.
 *
 * There are two high-level modules that most users will be interested in:
 * - gamepad_pmod_single: for a single controller;
 * - gamepad_pmod_dual: for two controllers.
 * 
 * There are also two lower-level modules that you can use if you want to
 * handle the interfacing yourself:
 * - gamepad_pmod_driver: interfaces with the Pmod and provides the raw data;
 * - gamepad_pmod_decoder: decodes the raw data into button states.
 *
 * The docs, schematics, PCB files, and firmware code for the Gamepad Pmod
 * are available at https://github.com/psychogenic/gamepad-pmod.
 */

/**
 * gamepad_pmod_driver -- Serial interface for the Gamepad Pmod.
 *
 * This module reads raw data from the Gamepad Pmod *serially*
 * and stores it in a shift register. When the latch signal is received, 
 * the data is transferred into `data_reg` for further processing.
 *
 * Functionality:
 *   - Synchronizes the `pmod_data`, `pmod_clk`, and `pmod_latch` signals 
 *     to the system clock domain.
 *   - Captures serial data on each falling edge of `pmod_clk`.
 *   - Transfers the shifted data into `data_reg` when `pmod_latch` goes low.
 *
 * Parameters:
 *   - `BIT_WIDTH`: Defines the width of `data_reg` (default: 24 bits).
 *
 * Inputs:
 *   - `rst_n`: Active-low reset.
 *   - `clk`: System clock.
 *   - `pmod_data`: Serial data input from the Pmod.
 *   - `pmod_clk`: Serial clock from the Pmod.
 *   - `pmod_latch`: Latch signal indicating the end of data transmission.
 *
 * Outputs:
 *   - `data_reg`: Captured parallel data after shifting is complete.
 */
module gamepad_pmod_driver #(
    parameter BIT_WIDTH = 24
) (
    input wire rst_n,
    input wire clk,
    input wire pmod_data,
    input wire pmod_clk,
    input wire pmod_latch,
    output reg [BIT_WIDTH-1:0] data_reg
);

  reg pmod_clk_prev;
  reg pmod_latch_prev;
  reg [BIT_WIDTH-1:0] shift_reg;

  // Sync Pmod signals to the clk domain:
  reg [1:0] pmod_data_sync;
  reg [1:0] pmod_clk_sync;
  reg [1:0] pmod_latch_sync;

  always @(posedge clk) begin
    if (~rst_n) begin
      pmod_data_sync  <= 2'b0;
      pmod_clk_sync   <= 2'b0;
      pmod_latch_sync <= 2'b0;
    end else begin
      pmod_data_sync  <= {pmod_data_sync[0], pmod_data};
      pmod_clk_sync   <= {pmod_clk_sync[0], pmod_clk};
      pmod_latch_sync <= {pmod_latch_sync[0], pmod_latch};
    end
  end

  always @(posedge clk) begin
    if (~rst_n) begin
      /* Initialize data and shift registers to all 1s so they're detected as "not present".
       * This accounts for cases where we have:
       *  - setup for 2 controllers;
       *  - only a single controller is connected; and
       *  - the driver in those cases only sends bits for a single controller.
       */
      data_reg <= {BIT_WIDTH{1'b1}};
      shift_reg <= {BIT_WIDTH{1'b1}};
      pmod_clk_prev <= 1'b0;
      pmod_latch_prev <= 1'b0;
    end
    begin
      pmod_clk_prev   <= pmod_clk_sync[1];
      pmod_latch_prev <= pmod_latch_sync[1];

      // Capture data on rising edge of pmod_latch:
      if (pmod_latch_sync[1] & ~pmod_latch_prev) begin
        data_reg <= shift_reg;
      end

      // Sample data on rising edge of pmod_clk:
      if (pmod_clk_sync[1] & ~pmod_clk_prev) begin
        shift_reg <= {shift_reg[BIT_WIDTH-2:0], pmod_data_sync[1]};
      end
    end
  end

endmodule


/**
 * gamepad_pmod_decoder -- Decodes raw data from the Gamepad Pmod.
 *
 * This module takes a 12-bit parallel data register (`data_reg`) 
 * and decodes it into individual button states. It also determines
 * whether a controller is connected.
 *
 * Functionality:
 *   - If `data_reg` contains all `1's` (`0xFFF`), it indicates that no controller is connected.
 *   - Otherwise, it extracts individual button states from `data_reg`.
 *
 * Inputs:
 *   - `data_reg [11:0]`: Captured button state data from the gamepad.
 *
 * Outputs:
 *   - `b, y, select, start, up, down, left, right, a, x, l, r`: Individual button states (`1` = pressed, `0` = released).
 *   - `is_present`: Indicates whether a controller is connected (`1` = connected, `0` = not connected).
 */
module gamepad_pmod_decoder (
    input wire [11:0] data_reg,
    output wire b,
    output wire y,
    output wire select,
    output wire start,
    output wire up,
    output wire down,
    output wire left,
    output wire right,
    output wire a,
    output wire x,
    output wire l,
    output wire r,
    output wire is_present
);

  // When the controller is not connected, the data register will be all 1's
  wire reg_empty = (data_reg == 12'hfff);
  assign is_present = reg_empty ? 0 : 1'b1;
  assign {b, y, select, start, up, down, left, right, a, x, l, r} = reg_empty ? 0 : data_reg;

endmodule


/**
 * gamepad_pmod_single -- Main interface for a single Gamepad Pmod controller.
 * 
 * This module provides button states for a **single controller**, reducing 
 * resource usage (fewer flip-flops) compared to a dual-controller version.
 * 
 * Inputs:
 *   - `pmod_data`, `pmod_clk`, and `pmod_latch` are the signals from the PMOD interface.
 * 
 * Outputs:
 *   - Each button's state is provided as a single-bit wire (e.g., `start`, `up`, etc.).
 *   - `is_present` indicates whether the controller is connected (`1` = connected, `0` = not detected).
 */
module gamepad_pmod_single (
    input wire rst_n,
    input wire clk,
    input wire pmod_data,
    input wire pmod_clk,
    input wire pmod_latch,

    output wire b,
    output wire y,
    output wire select,
    output wire start,
    output wire up,
    output wire down,
    output wire left,
    output wire right,
    output wire a,
    output wire x,
    output wire l,
    output wire r,
    output wire is_present
);

  wire [11:0] gamepad_pmod_data;

  gamepad_pmod_driver #(
      .BIT_WIDTH(12)
  ) driver (
      .rst_n(rst_n),
      .clk(clk),
      .pmod_data(pmod_data),
      .pmod_clk(pmod_clk),
      .pmod_latch(pmod_latch),
      .data_reg(gamepad_pmod_data)
  );

  gamepad_pmod_decoder decoder (
      .data_reg(gamepad_pmod_data),
      .b(b),
      .y(y),
      .select(select),
      .start(start),
      .up(up),
      .down(down),
      .left(left),
      .right(right),
      .a(a),
      .x(x),
      .l(l),
      .r(r),
      .is_present(is_present)
  );

endmodule


/**
 * gamepad_pmod_dual -- Main interface for the Pmod gamepad.
 * This module provides button states for two controllers using
 * 2-bit vectors for each button (e.g., start[1:0], up[1:0], etc.).
 * 
 * Each button state is represented as a 2-bit vector:
 *   - Index 0 corresponds to the first controller (e.g., up[0], y[0], etc.).
 *   - Index 1 corresponds to the second controller (e.g., up[1], y[1], etc.).
 *
 * The `is_present` signal indicates whether a controller is connected:
 *   - `is_present[0] == 1` when the first controller is connected.
 *   - `is_present[1] == 1` when the second controller is connected.
 *
 * Inputs:
 *   - `pmod_data`, `pmod_clk`, and `pmod_latch` are the 3 wires coming from the Pmod interface.
 *
 * Outputs:
 *   - Button state vectors for each controller.
 *   - Presence detection via `is_present`.
 */
module gamepad_pmod_dual (
    input wire rst_n,
    input wire clk,
    input wire pmod_data,
    input wire pmod_clk,
    input wire pmod_latch,

    output wire [1:0] b,
    output wire [1:0] y,
    output wire [1:0] select,
    output wire [1:0] start,
    output wire [1:0] up,
    output wire [1:0] down,
    output wire [1:0] left,
    output wire [1:0] right,
    output wire [1:0] a,
    output wire [1:0] x,
    output wire [1:0] l,
    output wire [1:0] r,
    output wire [1:0] is_present
);

  wire [23:0] gamepad_pmod_data;

  gamepad_pmod_driver driver (
      .rst_n(rst_n),
      .clk(clk),
      .pmod_data(pmod_data),
      .pmod_clk(pmod_clk),
      .pmod_latch(pmod_latch),
      .data_reg(gamepad_pmod_data)
  );

  gamepad_pmod_decoder decoder1 (
      .data_reg(gamepad_pmod_data[11:0]),
      .b(b[0]),
      .y(y[0]),
      .select(select[0]),
      .start(start[0]),
      .up(up[0]),
      .down(down[0]),
      .left(left[0]),
      .right(right[0]),
      .a(a[0]),
      .x(x[0]),
      .l(l[0]),
      .r(r[0]),
      .is_present(is_present[0])
  );

  gamepad_pmod_decoder decoder2 (
      .data_reg(gamepad_pmod_data[23:12]),
      .b(b[1]),
      .y(y[1]),
      .select(select[1]),
      .start(start[1]),
      .up(up[1]),
      .down(down[1]),
      .left(left[1]),
      .right(right[1]),
      .a(a[1]),
      .x(x[1]),
      .l(l[1]),
      .r(r[1]),
      .is_present(is_present[1])
  );

endmodule

`default_nettype wire