//////////////////////////////////////////////////////////////////////
////                                                              ////
////  OR1200's FPU Wrapper                                        ////
////                                                              ////
////  This file is part of the OpenRISC 1200 project              ////
////  http://opencores.org/project,or1k                           ////
////                                                              ////
////  Description                                                 ////
////  Wrapper for floating point unit.                            ////
////  Interface based on MULT/MAC unit.                           ////
////                                                              ////
////  To Do:                                                      ////
////   - remainder instruction implementation                     ////
////   - registering in/around compare unit                       ////
////                                                              ////
////  Author(s):                                                  ////
////      - Julius Baxter, julius@opencores.org                   ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2009 Authors and OPENCORES.ORG                 ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

// synopsys translate_off
`include "timescale.v"
// synopsys translate_on
`include "or1200_defines.v"

module or1200_fpu(
		  // Clock and reset
		  clk, rst,

		  // FPU interface
		  ex_freeze, a, b, fpu_op, result,

		  // Flag controls
		  flagforw, flag_we,

		  // Exception signal
		  sig_fp, except_started,

		  // SPR interface
		  fpcsr_we, fpcsr,
		  spr_cs, spr_write, spr_addr, spr_dat_i, spr_dat_o
		  );

   parameter width = `OR1200_OPERAND_WIDTH;

   //
   // I/O
   //

   //
   // Clock and reset
   //
   input				clk;
   input				rst;

   //
   // FPU interface
   //
   input				ex_freeze;
   input [width-1:0] 			a;
   input [width-1:0] 			b;
   input [`OR1200_FPUOP_WIDTH-1:0] 	fpu_op;
   output [width-1:0] 			result;

   //
   // Flag signals
   //
   output 				flagforw;
   output 				flag_we;
   
   
   //
   // FPCSR interface
   //  
   input 				fpcsr_we;   
   output [`OR1200_FPCSR_WIDTH-1:0] 	fpcsr;

   //
   // Exception signal
   //   
   output 				sig_fp;
   input 				except_started;
   
   
   //
   // SPR interface
   //
   input				spr_cs;
   input				spr_write;
   input [31:0] 			spr_addr;
   input [31:0] 			spr_dat_i;
   output [31:0] 			spr_dat_o;

   //
   // Internals
   //
   reg [2:0] 				fpu_op_count;
   reg [`OR1200_FPUOP_WIDTH:0] 		fpu_op_r;   
   reg [`OR1200_FPCSR_WIDTH-1:0] 	fpcsr_r;
   reg 					fpu_latch_operand;
   wire 				fpu_check_op;   
   wire 				fpu_latch_op;
   wire 				inf, snan, qnan, ine, overflow, 
					underflow, zero, div_by_zero;
   wire 				fpu_op_is_comp, fpu_op_r_is_comp;   
   wire 				altb, blta, aeqb, cmp_inf, cmp_zero, 
					unordered ;
   reg 					flag;
   
   assign fpcsr = fpcsr_r;
   
   assign sig_fp = fpcsr_r[`OR1200_FPCSR_FPEE] 
	    & (|fpcsr_r[`OR1200_FPCSR_WIDTH-1:`OR1200_FPCSR_OVF]);

   // Generate signals to latch fpu_op from decode instruction, then latch 
   // operands when they appear during execute stage
   
   assign fpu_check_op = (!ex_freeze & fpu_op[`OR1200_FPUOP_WIDTH-1]);

   assign fpu_op_is_comp = fpu_op[3];

   assign fpu_op_r_is_comp = fpu_op_r[3];   

   assign fpu_latch_op = fpu_check_op & !fpu_op_is_comp;   
   
   always @(posedge clk) 
     fpu_latch_operand <= fpu_check_op & !fpu_op_is_comp;

   // Register fpu_op on comparisons, clear otherwise, remove top bit
   always @(posedge clk)
     fpu_op_r <= (fpu_check_op & fpu_op_is_comp) ? 
		 {1'b0,fpu_op[`OR1200_FPUOP_WIDTH-2:0]} : !ex_freeze ? 
		 0 : fpu_op_r;   

   //
   // Counter for each FPU operation
   // Loaded at start, counts down
   //
   always @(posedge clk or posedge rst) begin
      if (rst)
	fpu_op_count <= 0;
      else
	if (|fpu_op_count)
	  fpu_op_count <= fpu_op_count - 1;
	else if(fpu_check_op)
	  fpu_op_count <= 5;
   end

   //
   // FPCSR register
   //   
   always @(posedge clk or posedge rst) begin
      if (rst)
	fpcsr_r <= 0;
      else
	begin
	   if (fpcsr_we)
	     fpcsr_r <= b[`OR1200_FPCSR_WIDTH-1:0];
           else if (fpu_op_count == 1)
	     begin
		fpcsr_r[`OR1200_FPCSR_OVF] <= overflow;
		fpcsr_r[`OR1200_FPCSR_UNF] <= underflow;
		fpcsr_r[`OR1200_FPCSR_SNF] <= snan;
		fpcsr_r[`OR1200_FPCSR_QNF] <= qnan;
		fpcsr_r[`OR1200_FPCSR_ZF]  <= zero | 
					      (cmp_zero & fpu_op_r_is_comp);
		fpcsr_r[`OR1200_FPCSR_IXF] <= ine;
		fpcsr_r[`OR1200_FPCSR_IVF] <= 0; // Not used by this FPU
		fpcsr_r[`OR1200_FPCSR_INF] <= inf | 
					      (cmp_inf & fpu_op_r_is_comp);
		fpcsr_r[`OR1200_FPCSR_DZF] <= div_by_zero;
	     end // if (fpu_op_count == 1)
	   if (except_started)
	     fpcsr_r[`OR1200_FPCSR_FPEE] <= 0;
	end // else: !if(rst)
   end // always @ (posedge clk or posedge rst)

   //
   // Comparison flag generation
   //
   always@(posedge clk)
     begin
	if (fpu_op_r_is_comp)
	  begin
	     case(fpu_op_r)
	       `OR1200_FPCOP_SFEQ: begin
		  flag <= aeqb;
	       end
	       `OR1200_FPCOP_SFNE: begin
		  flag <= !aeqb;
	       end
	       `OR1200_FPCOP_SFGT: begin
		  flag <= blta & !aeqb;
	       end
	       `OR1200_FPCOP_SFGE: begin
		  flag <= blta | aeqb;
	       end
	       `OR1200_FPCOP_SFLT: begin
		  flag <= altb & !aeqb;
	       end
	       `OR1200_FPCOP_SFLE: begin
		  flag <= altb | aeqb;
	       end
	       default: begin
		  flag <= 0;
	       end
	     endcase // case (fpu_op_r)
	  end // if (fpu_op_r_is_comp)
	else
	  flag <= 0;
     end // always@ (posedge clk)
   
   assign flagforw = flag;
   
   // Determine here where we do the write, ie how much we pipeline the 
   // comparison   
   assign flag_we = fpu_op_r_is_comp & (fpu_op_count == 2);

   // FP arithmetic module
   fpu fpu0
     ( 
       .clk(clk), 
       .rmode(fpcsr_r[`OR1200_FPCSR_RM]),
       .fpu_op(fpu_op[2:0]), 
       .opa(a), 
       .opb(b), 
       .out(result),
       .latch_operand(fpu_latch_operand),
       .latch_op(fpu_latch_op),
       .inf(inf),
       .snan(snan),
       .qnan(qnan),
       .ine(ine),
       .overflow(overflow),
       .underflow(underflow),
       .zero(zero),
       .div_by_zero(div_by_zero)
       );

   // FP comparator
   fcmp fcmp0
     (
      .opa(a), 
      .opb(b), 
      .unordered(unordered),
      // I am convinced the comparison logic is wrong way around in this 
      // module, simplest to swap them on output -- julius
       
      .altb(blta), 
      .blta(altb), 
      .aeqb(aeqb), 
      .inf(cmp_inf), 
      .zero(cmp_zero));
   

endmodule // or1200_fpu
