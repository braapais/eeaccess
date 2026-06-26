/*
  Open-back, open-bottom box with long faces made from planks.

  Dimensions:
    Clear internal footprint inside battens:
      1000 mm wide x 500 mm deep

    Overall modeled footprint:
      1070 mm wide x 635 mm deep x 600 mm high

    Facing the box, the left side panels stop at the rear edge of the
    3rd top panel.

  Material thickness:
    10 mm

  Planks:
    - Front: 4 planks, 1070 x 100 x 10 mm, with equal gaps.
    - Left: 4 panels, 456.67 x 100 x 10 mm.
    - Right: 4 panels, 635 x 100 x 10 mm.
      with the same 66.67 mm vertical gaps as the front.
    - Top: 3 planks, 1070 x 100 x 10 mm, plus rear plank shortened
      to 841.25 x 100 x 10 mm on the left side.
    - Internal vertical structure: 100 x 25 mm battens at corners and
      front/side fixing points.
    - Back and bottom are open.

  This is intentionally still a simple box. Use it as the starting point
  before adding vents, access openings, or support framing.
*/

$fn = 24;

clear_width_inside_battens = 1000;
clear_depth_inside_battens = 500;

box_height = 600;
panel_thickness = 10;
plank_width = 100;
batten_width = 100;
batten_depth = 25;
batten_height = box_height - panel_thickness;

box_width = clear_width_inside_battens + (2 * panel_thickness) + (2 * batten_depth);
box_depth = clear_depth_inside_battens + panel_thickness + batten_depth + batten_width;

front_plank_count = 4;
front_gap = (box_height - (front_plank_count * plank_width)) / (front_plank_count - 1);
side_plank_count = 4;
side_panel_height = plank_width;
top_plank_count = 4;
top_gap = (box_depth - (top_plank_count * plank_width)) / (top_plank_count - 1);
left_side_ends_at_top_panel = 3;
left_side_depth = (left_side_ends_at_top_panel * plank_width)
  + ((left_side_ends_at_top_panel - 1) * top_gap);

left_batten_x_position = -box_width / 2 + panel_thickness + batten_depth / 2;
right_batten_x_position = box_width / 2 - panel_thickness - batten_depth / 2;
first_middle_front_batten_x = left_batten_x_position
  + ((right_batten_x_position - left_batten_x_position) / 4);
rear_top_shorten = first_middle_front_batten_x + (box_width / 2) - (batten_width / 2);

wood_color = [0.72, 0.45, 0.24];

module panel(size, position) {
  color(wood_color)
    translate(position)
      cube(size, center = true);
}

module front_batten(position) {
  color([0.55, 0.31, 0.16])
    translate(position)
      cube([batten_width, batten_depth, batten_height], center = true);
}

module side_batten(position) {
  color([0.55, 0.31, 0.16])
    translate(position)
      cube([batten_depth, batten_width, batten_height], center = true);
}

module top_cross_rail(position) {
  color([0.55, 0.31, 0.16])
    translate(position)
      cube([batten_width, box_depth, batten_depth], center = true);
}

module closed_box() {
  // Internal vertical battens.
  front_batten_y = -box_depth / 2 + panel_thickness + batten_depth / 2;
  left_batten_x = -box_width / 2 + panel_thickness + batten_depth / 2;
  right_batten_x = box_width / 2 - panel_thickness - batten_depth / 2;

  // Side battens align with the top panel centres.
  for (i = [0 : left_side_ends_at_top_panel - 1]) {
    y = -box_depth / 2 + plank_width / 2 + i * (plank_width + top_gap);
    side_batten([left_batten_x, y, batten_height / 2]);
  }

  for (i = [0 : top_plank_count - 1]) {
    y = -box_depth / 2 + plank_width / 2 + i * (plank_width + top_gap);
    side_batten([right_batten_x, y, batten_height / 2]);
  }

  // Front middle: 3 battens between the side-aligned corner battens.
  for (i = [1 : 3]) {
    x = left_batten_x + i * ((right_batten_x - left_batten_x) / 4);
    front_batten([x, front_batten_y, batten_height / 2]);
  }

  // Three rails under the top panels, aligned with the middle front battens.
  for (i = [1 : 3]) {
    x = left_batten_x + i * ((right_batten_x - left_batten_x) / 4);
    top_cross_rail([x, 0, box_height - panel_thickness - batten_depth / 2]);
  }

  // Front: 4 planks, with equal gaps between planks.
  for (i = [0 : front_plank_count - 1]) {
    z = plank_width / 2 + i * (plank_width + front_gap);

    panel(
      [box_width, panel_thickness, plank_width],
      [0, -box_depth / 2 + panel_thickness / 2, z]
    );
  }

  // Left and right: 4 panels per face, using the same vertical gap as the front.
  for (i = [0 : side_plank_count - 1]) {
    z = side_panel_height / 2 + i * (side_panel_height + front_gap);

    panel(
      [panel_thickness, left_side_depth, side_panel_height],
      [-box_width / 2 + panel_thickness / 2, -box_depth / 2 + left_side_depth / 2, z]
    );
    panel(
      [panel_thickness, box_depth, side_panel_height],
      [box_width / 2 - panel_thickness / 2, 0, z]
    );
  }

  // Top: 4 planks, with equal gaps between planks.
  for (i = [0 : top_plank_count - 1]) {
    y = -box_depth / 2 + plank_width / 2 + i * (plank_width + top_gap);
    top_length = i == top_plank_count - 1 ? box_width - rear_top_shorten : box_width;
    top_x = i == top_plank_count - 1 ? rear_top_shorten / 2 : 0;

    panel(
      [top_length, plank_width, panel_thickness],
      [top_x, y, box_height - panel_thickness / 2]
    );
  }

  // Support the new left end of the shortened rear top plank.
  rear_top_y = -box_depth / 2 + plank_width / 2 + (top_plank_count - 1) * (plank_width + top_gap);
  rear_top_back_edge_y = rear_top_y + plank_width / 2;
  rear_batten_y = rear_top_back_edge_y - batten_depth / 2;
  rear_top_left_edge_x = -box_width / 2 + rear_top_shorten;
  rear_top_left_support_x = first_middle_front_batten_x;
  rear_top_right_support_x = right_batten_x;
  front_batten([rear_top_left_support_x, rear_batten_y, batten_height / 2]);

  // Rear stabilizer aligned to the back edge of the rear top panel.
  front_batten([rear_top_right_support_x - (batten_depth + batten_width) / 2, rear_batten_y, batten_height / 2]);
}

closed_box();

/*
  Basic panel list:
    - Front: 4 x 1070 x 100 x 10 mm
      Gaps between planks: 66.67 mm
    - Left: 4 x 456.67 x 100 x 10 mm
      Gaps between panels: 66.67 mm
    - Right: 4 x 635 x 100 x 10 mm
      Gaps between panels: 66.67 mm
    - Top: 3 x 1070 x 100 x 10 mm
    - Rear top: 1 x 841.25 x 100 x 10 mm, shortened 228.75 mm on the left
      Gaps between planks: 78.33 mm
    - Internal vertical battens:
      3 middle front battens: 100 x 25 x 590 mm
      8 side/support battens: 25 x 100 x 590 mm
      3 on the shortened left side, aligned with the first 3 top panels
      4 on the right side, aligned with all 4 top panels
      2 rear battens aligned with the back edge of the rear top panel
      3 top cross rails: 100 x 25 x 635 mm, under the top panels
      and aligned with the middle front battens
    - Back: open
    - Bottom: open

  Long planks:
    - 7 panels of 1070 x 100 x 10 mm
    - 1 panel of 841.25 x 100 x 10 mm

  Total side panels:
    - 4 panels of 456.67 x 100 x 10 mm
    - 4 panels of 635 x 100 x 10 mm

  Clear inside battens:
    - Width: 1000 mm
    - Depth: 500 mm

  Structural note:
    - The front battens reduce the unsupported front plank span
      from 1000 mm to about 235 mm.
    - The left side battens are redistributed over the shorter 456.67 mm side.
    - The right side battens remain distributed over the full 635 mm side.
    - The shortened rear top plank has a direct vertical support under
      its new left end.
*/
