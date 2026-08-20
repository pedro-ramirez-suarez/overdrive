[out:json][timeout:180];
(
 way["highway"="raceway"](50.415,5.920,50.470,6.020);
 way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential)$"]["name"](
50.415,5.920,50.470,6.020);
);
out geom;
