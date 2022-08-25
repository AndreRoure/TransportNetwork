
model PreProcessRoutesOSM 
 
global{
	
	file<geometry> osm <- file<geometry>(osm_file("../includes/brasilia.osm"));
	file road_shapefile <- file("../includes/roads.shp");
	
	file routes_json <- json_file("../includes/routes.json");
    map<string, list<string>> routes <- routes_json.contents;
	
	geometry shape <- envelope(osm);
	
	

	init {
		write "OSM file loaded: " + length(osm) + " geometries";
		
//		from the OSM file, creation of the selected agents	
		
		loop geom over: osm {
//			write geom get ("osm_id");
			if(length(geom.points) = 1 and geom get ("bus") = "yes") {
				create stop with: [shape::geom];
			}
			if(length(geom.points) > 1 and geom get ("building") != nil) {
				create building with: [shape::geom, type::string(geom get("building"))];
			}
		}
		
		create road from: road_shapefile with: [lanes::int(read("lanes")), oneway::string(read("oneway")), id::string(read("id"))] {
			geom_display <- shape + (2.5 * lanes);
			maxspeed <- (lanes = 1 ? 30.0 : (lanes = 2 ? 50.0 : 70.0)) °km / °h;
			switch oneway {
				match "no" {
					create road {
						lanes <- max([1, int(myself.lanes / 2.0)]);
						shape <- polyline(reverse(myself.shape.points));
						maxspeed <- myself.maxspeed;
						geom_display <- myself.geom_display;
						linked_road <- myself;
						myself.linked_road <- self;
					}
					lanes <- int(lanes / 2.0 + 0.5);
				}
				match "-1" {
					shape <- polyline(reverse(shape.points));
				}
			}
		}
		
		loop r over: routes.keys {
			list<string> points <- [];
			loop part over: routes[r]{
				ask road {
					if (id = part) {
						used <-  true;
						list<stop> stops <- agents_at_distance(25) of_species(stop);
						if (stops != nil) {
							ask stops {
								used <- true;
								add name to: points;
							}
						}
					}
				}
			}
			create route with: [name::r, stops::points];
		}
		
		write "stops and routes created";
		
		ask stop {
			if (!used) {
				do die;
			}			
		}
		write "filtering done";
		
		routes <- nil;
		
		ask route {
			routes[name] <- stops;
		}
		
		list<string> residential <- ["apartments","barracks","bungalow","cabin","detached","dormitory","farm","ger","hotel","house","houseboat","residential","semidetached_house","static_caravan","terrace"];
		list<string> commercial <- ["commercial","industrial","kiosk","office","retail","supermarket","warehouse"];
		ask building {
			if (type in residential) {
				type <-"residential";
			}
			else if (type in commercial) {
				type <- "commercial";
			}
			else {
				do die;
			}
		}
		
		//Save all the agents inside the file with the path written, using the with: facet to make a link between attributes and columns of the resulting shapefiles.
		save building type:"shp" to:"../includes/buildings.shp" attributes:["type"::type] ; 
		save stop type:"shp" to:"../includes/stops.shp" attributes:["name"::name] ;
		file f <- json_file("../includes/routesProcessed.json", routes);
		save f;

		write "files saved";
	}
}
	

species stop {
	bool used <- false;
	
	aspect default {
		draw circle(10) color: #blue;
	}
} 



species route {
	string name;
	list<string> stops;
}

species building {
	string type;
	aspect default{
		draw shape;
	}
}

species road skills: [skill_road] {
	string id;
	geometry geom_display;
	string oneway;

	bool used <- false;

	aspect default {
		draw shape color: (!used ? #black : #red) end_arrow: 5;
	}
}
	

experiment preProcess type: gui {
	output {
		display map type: opengl {
			species stop refresh: false  ;
			species road refresh: false  ;
			species building;
		}
	}
}