/*
  Alternative 2: louvered airflow AC cover.

  Same clear internal footprint inside battens:
    1000 mm wide x 500 mm deep x 600 mm high

  Design intent:
    - Open back and bottom.
    - Angled front and side louvers for better airflow than flat slats.
    - Top remains flat slatted cover.
    - Same asymmetric left side depth from the final design.
*/

$fn = 24;

clear_width_inside_battens = 1000;
clear_depth_inside_battens = 500;
box_height = 600;

panel_thickness = 10;
louver_width = 80;
batten_size = 40;
left_side_depth = 490;
louver_angle = 32;

box_width = clear_width_inside_battens + (2 * panel_thickness) + (2 * batten_size);
box_depth = clear_depth_inside_battens + panel_thickness + (2 * batten_size);

louver_count = 4;
top_slat_count = 4;

front_gap = (box_height - (louver_count * louver_width)) / (louver_count - 1);
top_gap = (box_depth - (top_slat_count * louver_width)) / (top_slat_count - 1);

rear_top_shorten = 100;

wood_color = [0.72, 0.45, 0.24];
batten_color = [0.55, 0.31, 0.16];

module part(size, position, color_value = wood_color) {
  color(color_value)
    translate(position)
      cube(size, center = true);
}

module batten(position) {
  part([batten_size, batten_size, box_height], position, batten_color);
}

module front_louver(z) {
  translate([0, -box_depth / 2 + panel_thickness / 2, z])
    rotate([louver_angle, 0, 0])
      part([box_width, panel_thickness, louver_width], [0, 0, 0]);
}

module side_louver(x, y_center, z, depth) {
  translate([x, y_center, z])
    rotate([0, x < 0 ? -louver_angle : louver_angle, 0])
      part([panel_thickness, depth, louver_width], [0, 0, 0]);
}

module battens() {
  front_y = -box_depth / 2 + panel_thickness + batten_size / 2;
  rear_y = box_depth / 2 - batten_size / 2;
  left_rear_y = -box_depth / 2 + left_side_depth - batten_size / 2;
  left_x = -box_width / 2 + panel_thickness + batten_size / 2;
  right_x = box_width / 2 - panel_thickness - batten_size / 2;

  for (i = [0 : 4]) {
    x = left_x + i * ((right_x - left_x) / 4);
    batten([x, front_y, box_height / 2]);
  }

  for (i = [1 : 3]) {
    batten([left_x, front_y + i * ((left_rear_y - front_y) / 3), box_height / 2]);
    batten([right_x, front_y + i * ((rear_y - front_y) / 3), box_height / 2]);
  }

  rear_top_y = -box_depth / 2 + louver_width / 2 + (top_slat_count - 1) * (louver_width + top_gap);
  rear_top_left_edge_x = -box_width / 2 + rear_top_shorten;
  batten([rear_top_left_edge_x + batten_size / 2, rear_top_y, box_height / 2]);
}

module louvered_cover() {
  battens();

  for (i = [0 : louver_count - 1]) {
    z = louver_width / 2 + i * (louver_width + front_gap);
    front_louver(z);
    side_louver(-box_width / 2 + panel_thickness / 2, -box_depth / 2 + left_side_depth / 2, z, left_side_depth);
    side_louver(box_width / 2 - panel_thickness / 2, 0, z, box_depth);
  }

  for (i = [0 : top_slat_count - 1]) {
    y = -box_depth / 2 + louver_width / 2 + i * (louver_width + top_gap);
    top_length = i == top_slat_count - 1 ? box_width - rear_top_shorten : box_width;
    top_x = i == top_slat_count - 1 ? rear_top_shorten / 2 : 0;
    part([top_length, louver_width, panel_thickness], [top_x, y, box_height - panel_thickness / 2]);
  }
}

louvered_cover();

/*
  Approximate cut list:
    Front louvers: 4 x 1100 x 80 x 10 mm
    Left side louvers: 4 x 490 x 80 x 10 mm
    Right side louvers: 4 x 590 x 80 x 10 mm
    Top slats: 3 x 1100 x 80 x 10 mm
    Rear top slat: 1 x 1000 x 80 x 10 mm
    Battens: 12 x 40 x 40 x 600 mm
*/
