[out:json][timeout:180];
(
 way["highway"~"^(primary|secondary|tertiary|unclassified)$"](46.500,10.420,46.560,10.520);
);
out geom;
