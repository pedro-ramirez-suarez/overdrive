[out:json][timeout:180];
(
 way["building"](43.727,7.405,43.752,7.445);
 way["landuse"~"^(forest|grass|meadow|village_green)$"](43.727,7.405,43.752,7.445);
 way["natural"~"^(wood|scrub)$"](43.727,7.405,43.752,7.445);
 way["leisure"~"^(park|garden|pitch)$"](43.727,7.405,43.752,7.445);
);
out geom;
