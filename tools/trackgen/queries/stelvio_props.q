[out:json][timeout:180];
(
 way["building"](46.500,10.420,46.560,10.520);
 way["natural"~"^(wood|scrub|bare_rock|scree)$"](46.500,10.420,46.560,10.520);
 way["landuse"~"^(forest|meadow|grass)$"](46.500,10.420,46.560,10.520);
);
out geom;
