--   __   __     __  __     __         __
--  /\ "-.\ \   /\ \/\ \   /\ \       /\ \
--  \ \ \-.  \  \ \ \_\ \  \ \ \____  \ \ \____
--   \ \_\\"\_\  \ \_____\  \ \_____\  \ \_____\
--    \/_/ \/_/   \/_____/   \/_____/   \/_____/
--   ______     ______       __     ______     ______     ______
--  /\  __ \   /\  == \     /\ \   /\  ___\   /\  ___\   /\__  _\
--  \ \ \/\ \  \ \  __<    _\_\ \  \ \  __\   \ \ \____  \/_/\ \/
--   \ \_____\  \ \_____\ /\_____\  \ \_____\  \ \_____\    \ \_\
--    \/_____/   \/_____/ \/_____/   \/_____/   \/_____/     \/_/
--
-- https://joshbassett.info
-- https://twitter.com/nullobject
-- https://github.com/nullobject
--
-- Copyright (c) 2020 Josh Bassett
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.common.all;

-- The character layer is the part of the graphics pipeline that handles things
-- like the logo, score, playfield, and other static graphics.
--
-- It consists of a 32x32 grid of 8x8 tiles.
entity char_layer is
  port (
    -- clock signals
    clk   : in std_logic;
    cen_6 : in std_logic;

    -- char RAM
    ram_addr : out unsigned(CHAR_RAM_GPU_ADDR_WIDTH-1 downto 0);
    ram_data : in std_logic_vector(CHAR_RAM_GPU_DATA_WIDTH-1 downto 0);

    -- tile ROM
    rom_addr : out unsigned(CHAR_ROM_ADDR_WIDTH-1 downto 0);
    rom_data : in std_logic_vector(CHAR_ROM_DATA_WIDTH-1 downto 0);

    -- video signals
    video : in video_t;

    -- graphics data
    data : out byte_t
  );
end char_layer;

architecture arch of char_layer is
  -- represents the position of a pixel in a 8x8 tile
  type tile_pos_t is record
    x : unsigned(2 downto 0);
    y : unsigned(2 downto 0);
  end record tile_pos_t;

  -- tile signals
  signal tile_data  : byte_t;
  signal tile_code  : tile_code_t;
  signal tile_color : tile_color_t;
  signal tile_row   : tile_row_t;
  signal tile_pixel : tile_pixel_t;

  -- aliases to extract the components of the horizontal and vertical position
  alias col      : unsigned(4 downto 0) is video.pos.x(7 downto 3);
  alias row      : unsigned(4 downto 0) is video.pos.y(7 downto 3);
  alias offset_x : unsigned(2 downto 0) is video.pos.x(2 downto 0);
  alias offset_y : unsigned(2 downto 0) is video.pos.y(2 downto 0);
begin
  -- Load tile data from the character RAM.
  --
  -- While the current tile is being rendered, we need to fetch data for the
  -- next tile ahead, so that it is loaded in time to render it on the screen.
  --
  -- The 16-bit tile data words aren't stored contiguously in RAM, instead they
  -- are split into high and low bytes. The high bytes are stored in the
  -- upper-half of the RAM, while the low bytes are stored in the lower-half.
  --
  -- We latch the tile code well before the end of the row, to allow the GPU
  -- enough time to fetch pixel data from the tile ROM.
  tile_data_pipeline : process (clk)
  begin
    if rising_edge(clk) then
      if cen_6 = '1' then
        case to_integer(offset_x) is
          when 0 =>
            -- load high byte
            ram_addr <= '1' & row & (col+1);

          when 1 =>
            -- latch high byte
            tile_data <= ram_data;

            -- load low byte
            ram_addr <= '0' & row & (col+1);

          when 2 =>
            -- latch tile code
            tile_code <= unsigned(tile_data(2 downto 0) & ram_data);

          when 7 =>
            -- latch colour
            tile_color <= tile_data(7 downto 4);

          when others => null;
        end case;
      end if;
    end if;
  end process;

  -- latch the next row from the tile ROM when rendering the last pixel in
  -- every row
  latch_tile_row : process (clk)
  begin
    if rising_edge(clk) then
      if cen_6 = '1' then
        if video.pos.x(2 downto 0) = 7 then
          tile_row <= rom_data;
        end if;
      end if;
    end if;
  end process;

  -- Set the tile ROM address.
  --
  -- This address points to a row of an 8x8 tile.
  rom_addr <= tile_code(9 downto 0) & offset_y(2 downto 0);

  -- decode the pixel from the tile row data
  tile_pixel <= decode_tile_row(tile_row, video.pos.x(2 downto 0));

  -- set graphics data
  data <= tile_color & tile_pixel;
end architecture arch;
