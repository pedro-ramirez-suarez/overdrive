[out:json][timeout:180];
(
 way["building"](50.325,6.900,50.395,7.020);
 way["landuse"~"^(forest|meadow|grass)$"](50.325,6.900,50.395,7.020);
 way["natural"~"^(wood|scrub)$"](50.325,6.900,50.395,7.020);
);
out geom;
