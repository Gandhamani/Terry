`timescale 1ns / 1ps

module UARTTX #(
  parameter CLKS_PER_BIT = 651,
  parameter FIFO_DEPTH = 16
)(
  input  wire        i_clk,
  input  wire        i_rst,
  input  wire [7:0]  i_TX_Byte,
  input  wire        i_TX_DV,
  output wire        o_TX_Active,
  output wire        o_TX_Serial,
  output wire        o_TX_Done
);

  // FSM States
  typedef enum logic [2:0] {
    IDLE,
    START_BIT,
    DATA_BITS,
    PARITY_BIT,
    STOP_BIT,
    CLEANUP
  } state_t;

  state_t r_state = IDLE;

  // FIFO
  reg [7:0] fifo_mem [0:FIFO_DEPTH-1];
  reg [$clog2(FIFO_DEPTH):0] wr_ptr = 0;
  reg [$clog2(FIFO_DEPTH):0] rd_ptr = 0;

  wire fifo_empty = (wr_ptr == rd_ptr);
  wire fifo_full  = (wr_ptr - rd_ptr) == FIFO_DEPTH;
  wire [7:0] fifo_dout = fifo_mem[rd_ptr[$clog2(FIFO_DEPTH)-1:0]];

  // Baud pulse generator
  reg [15:0] baud_cnt = 0;
  reg baud_pulse = 0;

  always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
      baud_cnt <= 0;
      baud_pulse <= 0;
    end else if (r_state != IDLE) begin
      if (baud_cnt == CLKS_PER_BIT - 1) begin
        baud_cnt <= 0;
        baud_pulse <= 1;
      end else begin
        baud_cnt <= baud_cnt + 1;
        baud_pulse <= 0;
      end
    end else begin
      baud_cnt <= 0;
      baud_pulse <= 0;
    end
  end
  // FIFO write logic
  always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
      wr_ptr <= 0;
    end else if (i_TX_DV && !fifo_full) begin
      fifo_mem[wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= i_TX_Byte;
      wr_ptr <= wr_ptr + 1;
    end
  end

  // UART TX logic
  reg [7:0] r_TX_Data = 0;
  reg [2:0] r_bit_index = 0;
  reg r_TX_Serial = 1;
  reg r_TX_Active = 0;
  reg r_TX_Done = 0;
  reg r_parity_bit = 0;

  always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
      r_state <= IDLE;
      rd_ptr <= 0;
      r_TX_Serial <= 1;
      r_TX_Active <= 0;
      r_TX_Done <= 0;
      r_bit_index <= 0;
    end else begin
      r_TX_Done <= 0;

      case (r_state)
        IDLE: begin
          r_TX_Serial <= 1;
          r_TX_Active <= 0;
          if (!fifo_empty) begin
            r_TX_Data <= fifo_dout;
            r_parity_bit <= ^fifo_dout; // Even parity
            rd_ptr <= rd_ptr + 1;
            r_state <= START_BIT;
            r_TX_Active <= 1;
          end
        end

        START_BIT: if (baud_pulse) begin
          r_TX_Serial <= 0;
          r_state <= DATA_BITS;
          r_bit_index <= 0;
        end

        DATA_BITS: if (baud_pulse) begin
          r_TX_Serial <= r_TX_Data[0];
          r_TX_Data <= r_TX_Data >> 1;
          if (r_bit_index == 7)
            r_state <= PARITY_BIT;
          else
            r_bit_index <= r_bit_index + 1;
        end

        PARITY_BIT: if (baud_pulse) begin
          r_TX_Serial <= r_parity_bit;
          r_state <= STOP_BIT;
        end

        STOP_BIT: if (baud_pulse) begin
          r_TX_Serial <= 1;
          r_state <= CLEANUP;
        end

        CLEANUP: if (baud_pulse) begin
          r_TX_Done <= 1;
          r_TX_Active <= 0;
          r_state <= IDLE;
        end
      endcase
    end
  end

  assign o_TX_Active = r_TX_Active;
  assign o_TX_Serial = r_TX_Serial;
  assign o_TX_Done   = r_TX_Done;

endmodule
`timescale 1ns / 1ps

module UARTRX #(
  parameter CLKS_PER_BIT = 651,
  parameter OVERSAMPLE = 16,
  parameter FIFO_DEPTH = 16
)(
  input wire        i_clk,
  input wire        i_rst,
  input wire        i_RX_Serial,
  input wire        i_RX_Read,
  output wire       o_RX_DV,
  output wire [7:0] o_RX_Byte
);

  // FIFO
  reg [7:0] fifo_mem [0:FIFO_DEPTH-1];
  reg [$clog2(FIFO_DEPTH):0] wr_ptr = 0;
  reg [$clog2(FIFO_DEPTH):0] rd_ptr = 0;

  wire fifo_full  = (wr_ptr - rd_ptr) == FIFO_DEPTH;
  wire fifo_empty = (wr_ptr == rd_ptr);
  wire [7:0] fifo_dout = fifo_mem[rd_ptr[$clog2(FIFO_DEPTH)-1:0]];

  // FSM States
  typedef enum logic [2:0] {
    IDLE,
    START_BIT,
    DATA_BITS,
    STOP_BIT
  } state_t;

  state_t r_state = IDLE;

  // Oversampling clock
  localparam integer CLKS_PER_SAMPLE = CLKS_PER_BIT / OVERSAMPLE;

  reg [15:0] sample_clk_cnt = 0;
  reg sample_tick = 0;

  always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
      sample_clk_cnt <= 0;
      sample_tick <= 0;
    end else begin
      if (sample_clk_cnt == CLKS_PER_SAMPLE - 1) begin
        sample_clk_cnt <= 0;
        sample_tick <= 1;
      end else begin
        sample_clk_cnt <= sample_clk_cnt + 1;
        sample_tick <= 0;
      end
    end
  end

  // UART RX logic
  reg [3:0] sample_index = 0;
  reg [3:0] bit_index = 0;
  reg [7:0] rx_shift = 0;

  always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
      r_state <= IDLE;
      sample_index <= 0;
      bit_index <= 0;
      wr_ptr <= 0;
    end else if (sample_tick) begin
      case (r_state)
        IDLE: begin
          if (i_RX_Serial == 0) begin // Start bit detected
            r_state <= START_BIT;
            sample_index <= 0;
          end
        end

        START_BIT: begin
          sample_index <= sample_index + 1;
          if (sample_index == 7) begin
            if (i_RX_Serial == 0) begin
              r_state <= DATA_BITS;
              sample_index <= 0;
              bit_index <= 0;
            end else begin
              r_state <= IDLE; // False start
            end
          end
        end

        DATA_BITS: begin
          sample_index <= sample_index + 1;
          if (sample_index == 7) begin
            rx_shift <= {i_RX_Serial, rx_shift[7:1]};
            sample_index <= 0;
            if (bit_index == 7) begin
              r_state <= STOP_BIT;
            end else begin
              bit_index <= bit_index + 1;
            end
          end
        end

        STOP_BIT: begin
          sample_index <= sample_index + 1;
          if (sample_index == 7) begin
            if (i_RX_Serial == 1 && !fifo_full) begin
              fifo_mem[wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= rx_shift;
              wr_ptr <= wr_ptr + 1;
            end
            r_state <= IDLE;
            sample_index <= 0;
          end
        end
      endcase
    end
  end

  // FIFO Read Logic
  always @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
      rd_ptr <= 0;
    end else if (i_RX_Read && !fifo_empty) begin
      rd_ptr <= rd_ptr + 1;
    end
  end

  assign o_RX_DV = !fifo_empty;
  assign o_RX_Byte = fifo_dout;

endmodule
