// Ordinary OpenSCAD source used to exercise WaifuCAD's external evaluator path.
$fn = 48;

difference() {
    union() {
        cube([40, 30, 8], center=true);
        translate([0, 0, 4]) cylinder(h=22, r1=9, r2=6);
    }
    translate([0, 0, -10]) cylinder(h=40, r=3.5);
}



