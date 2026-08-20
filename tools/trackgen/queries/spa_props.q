[out:json][timeout:180];
(
 way["building"](50.415,5.920,50.470,6.020);
 way["landuse"~"^(forest|grass|meadow|village_green)$"](50.415,5.920,50.470,6.020);
 way["natural"~"^(wood|scrub)$"](50.415,5.920,50.470,6.020);
 way["leisure"~"^(park|garden|pitch)$"](50.415,5.920,50.470,6.020);
);
out geom;
