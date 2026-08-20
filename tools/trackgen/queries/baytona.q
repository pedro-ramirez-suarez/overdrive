[out:json][timeout:180];
(
 way["highway"="raceway"](29.15,-81.11,29.23,-81.02);
 way["highway"~"^(motorway|trunk|primary|secondary|tertiary)$"]["name"](29.15,-81.11,29.23,-81.02);
);
out geom;
