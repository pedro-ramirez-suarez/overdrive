[out:json][timeout:180];
(
 way["building"](19.684,-101.152,19.736,-101.100);
 way["landuse"~"^(forest|grass|meadow|recreation_ground|village_green|cemetery)$"](19.684,-101.152,19.736,-101.100);
 way["leisure"~"^(park|garden|nature_reserve|pitch|golf_course)$"](19.684,-101.152,19.736,-101.100);
 way["natural"~"^(wood|scrub|heath)$"](19.684,-101.152,19.736,-101.100);
);
out geom;
