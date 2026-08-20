[out:json][timeout:180];
(
 way["highway"="raceway"](34.825,136.515,34.865,136.555);
 way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential)$"]["name"](
34.825,136.515,34.865,136.555);
);
out geom;
