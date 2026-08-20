[out:json][timeout:180];
(
 way["highway"="raceway"](19.385,-99.105,19.425,-99.065);
 way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential)$"]["name"](
19.385,-99.105,19.425,-99.065);
);
out geom;
