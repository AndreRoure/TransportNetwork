/**
* Name: TranspotNetwork
* Based on the internal empty template. 
* Author: andre
* Tags: 
*/


model TranspotNetwork

global {
	float percentageToBus;
	float percentageToWalk;
	float representationResolution;
	float respirationRate <- 1.1;
	int population;
	list<int> number;
	
	float virusQuanta;
	
	file building_shapefile <- file("../includes/buildings.shp");
	file road_shapefile <- file("../includes/roads.shp");
	file intersections_shapefile <- file("../includes/nodes.shp");
	file stops_shapefile <- file("../includes/stops.shp");
	
	file routes_json <- json_file("../includes/routesClean.json");
    map<string, list<string>> routes <- routes_json.contents;

	geometry shape <- envelope(road_shapefile);
	graph road_network;
	
	float Number <- 0.0;
	
//	general simulation
	init {
		step <- 1 °mn;
		starting_date <- date([2020,1,1,7,0,0]);
//		write starting_date.hour;
		
		create intersection from: intersections_shapefile with: [is_traffic_signal::(read("type") = "traffic_signals")];
		
		create road from: road_shapefile with: [lanes::int(read("lanes")), oneway::string(read("oneway")), maxspeed::float(read("maxspeed"))] {
			geom_display <- shape + (2.5 * lanes);
			float lanespeed <- (lanes = 1 ? 30.0 : (lanes = 2 ? 50.0 : 70.0)) °km / °h;
				if (oneway != "yes") {
					create road {
						lanes <- max([1, int(myself.lanes / 2.0)]);
						shape <- polyline(reverse(myself.shape.points));
						maxspeed <- max([lanespeed, maxspeed]);
						geom_display <- myself.geom_display;
						linked_road <- myself;
						myself.linked_road <- self;
					}
					lanes <- int(lanes / 2.0 + 0.5);
				}
		}
		
		map speed_map <- road as_map (each::(each.shape.perimeter / each.maxspeed));
		
		road_network <- (as_driving_graph(road, intersection)) with_weights speed_map;
		
		ask intersection {
			do initialize;
		}
		
		create building from: building_shapefile with: [type::string(read("type"))];
		create plataform from: stops_shapefile with: [name::string(read("name"))];
		
		
		loop r over: routes.keys {
			list<plataform> stops <- [];
			loop part over: routes[r]{
				ask plataform {
					if (self.name = part){
						add self to: stops;
					}
				}
			}
			create route with: [name::r, stops::stops];
		}
		
		create people number: population{
			home <- one_of(building where (each.type = "residential"));
			work <- one_of(building where (each.type = "commercial"));
		}
		
		ask route {
			create bus returns: b{
			max_speed <- 160 #km / #h;
			vehicle_length <- 10.0 #m;
			right_side_driving <- true;
			proba_lane_change_up <- 0.1 + (rnd(500) / 500);
			proba_lane_change_down <- 0.5 + (rnd(500) / 500);			
			location <- myself.location;
			security_distance_coeff <- 5 / 9 * 3.6 * (1.5 - rnd(1000) / 1000);
			proba_respect_priorities <- 1.0 - rnd(200 / 1000);
			proba_respect_stops <- [1.0];
			proba_block_node <- 0.0;
			proba_use_linked_road <- 0.0;
			max_acceleration <- 5 / 3.6;
			speed_coeff <- 1.2 - (rnd(400) / 1000);
			threshold_stucked <- int((1 + rnd(5)) #mn);
			proba_breakdown <- 0.00001;
			
		}
		ask b {
			stops <- copy(myself.stops);
			backup <- copy(myself.stops);
			route_name <- myself.name;
			do next;
		}
		ask stops {
			connections <- myself.stops + connections;
		}
		}
		ask plataform {
			connections <- distinct(connections);
			remove self from: connections;
		}
		
		ask people {
			do initialize;
		}
		ask any(people) {
			infected <- true;
		}
	}
	
	//TestUnit Init
//	init {
//		step <- 1 °mn;
//		starting_date <- date([2020,1,1,0,0,0]);
//		
//		create building {
//			type <- "experimentalOffice";
//			airChanges <- 810/0.7;
//			shape <- square(810/2);
//		}
//		create people number: population {
//			location <- any_location_in(any(building));
//		}
//		ask any(people) {
//			infected <- true;
//		}
//	}
	
	
		
}

species plataform parent: building{
	map<people,plataform> passengers;
	list<plataform> connections;
	
	aspect default {
		draw circle(10) color: #blue;
	}
} 

species building {
	string type;
	float airChanges <- shape.area * 2;
	int infectedNum;
	float activeQuanta <- 0.0;
	list<people> occupants;
	
	reflex contamination when: type = "commercial"{
		occupants <- people inside(self);
		infectedNum <- (occupants count(each.infected));
		activeQuanta <- (infectedNum * representationResolution * virusQuanta * respirationRate * step)/(airChanges * 3600);
		
		ask occupants {
			if (!self.infected) {
				do exposed(myself.activeQuanta);
			}
		}
	}
	
	aspect default {
		draw shape color: #black;
	}
	
	
}

species road skills: [skill_road] {
	geometry geom_display;
	string oneway;
	

	aspect default {
		draw shape color: #white end_arrow: 5;
	}
}

species people skills: [moving]{
	building target;
	building home;
	building work;
	int time_to_work;
	bool infected <- false;
	float exposedQuanta <- 0.0;
	rgb color <- #white;
	float speed <- 5 #km/#h;
	bool wait <- false;
	bool embark <- false;
	plataform bus_target;
	point foot_target;
	string method;

	
	action initialize {
		location <- home.location;
		time_to_work <- flip(0.1359) ? (rnd(6,9)) : (flip(0.3413) ? (rnd(9,12)) : (flip(0.3413) ? (rnd(12,15)) : (rnd(15,18))));
		if (distance_to(home,work) > 1 #km and flip(percentageToWalk)) {method <- "walk";}
		else if !empty(plataform at_distance(1 #km)) {
			ask work {
				if empty(plataform at_distance(1 #km)) {
					myself.method <- "car";
				}
				else {myself.method <- (flip(percentageToBus) ? "bus" : "car");}
			}
		}
		else {method <- "car";}
	}
	
	action exposed(float quanta) {
		exposedQuanta <- exposedQuanta + quanta;
	}
	
	reflex infectioProb when: current_date.hour = 23 and current_date.minute = 59{
		float p <- (1 - #e ^ (-exposedQuanta));
		if(flip(p)){
			infected <- true;
		}
	}
	
	
	
	reflex goWork when: current_date.hour = time_to_work and current_date.minute = 0{
		target <- work;
		do move;
	}
	
	reflex goHome when: current_date.hour = (time_to_work + 8) and current_date.minute = 0{
		if (location != home.location) {
			target <- home;
			do move;
		}
	}
	
	action move {
		switch method {
			match "walk"{do byFoot(target);}
			match "bus" {do byBus;}
			match "car" {do byCar;}
		}
	}
	
	action byFoot (building b) {
		foot_target <- (b).location;
	}
	
	reflex walking when: (foot_target != nil){
		do goto target: foot_target;
		if location = foot_target {
			foot_target <- nil;
		}
	}
	
	action byCar {
		color <- #transparent;
		point close_road <- ((road at_distance 1000) closest_to self).location;
		create vehicle returns: v{
			max_speed <- 160 #km / #h;
			vehicle_length <- 5.0 #m;
			right_side_driving <- true;
			proba_lane_change_up <- 0.1 + (rnd(500) / 500);
			proba_lane_change_down <- 0.5 + (rnd(500) / 500);			
			location <- close_road;
			security_distance_coeff <- 5 / 9 * 3.6 * (1.5 - rnd(1000) / 1000);
			proba_respect_priorities <- 1.0 - rnd(200 / 1000);
			proba_respect_stops <- [1.0];
			proba_block_node <- 0.0;
			proba_use_linked_road <- 0.0;
			max_acceleration <- 5 / 3.6;
			speed_coeff <- 1.2 - (rnd(400) / 1000);
			threshold_stucked <- int((1 + rnd(5)) #mn);
			proba_breakdown <- 0.00001;
			owner <- myself;
		}
		ask v {
			target <- myself.target;
		}
		wait <- true;
	}
	
	action routeFind {
		list<plataform> possible;
		list<plataform> common;
		plataform closest;
		ask target {
			possible <- plataform at_distance(1 #km);
		}
		list<plataform> near <- plataform at_distance(1 #km);
		
		
		loop p over: near {
			common <- p.connections inter possible;
			if !empty(common) {
				bus_target <- common closest_to target;
				return p;
			}
		}
		
		return nil;
	}
	
	action byBus {
		plataform possible <- routeFind();
		if !(possible = nil) {
			do byFoot(possible);
			embark <- true;
		}
	}
	
	reflex getBus when: (method = "bus" and embark and foot_target = nil) {
		embark <- false;
		plataform focus <- plataform at_distance(10) closest_to self;
		if (focus != nil) {
			ask focus {
				passengers[myself] <- myself.bus_target;
			}
		}
	}
	
	aspect default {
		draw circle(2) color:infected ? #green : color;
	}
}

species vehicle skills: [advanced_driving] {
	rgb color <- rnd_color(255);
	int counter_stucked <- 0;
	int threshold_stucked;
	bool breakdown <- false;
	float proba_breakdown;
	building target;
	
	people owner;

	action pathFind {
		intersection real_target <- (intersection closest_to target);
		current_path <- compute_path(graph: road_network, target: real_target);
		target <- nil;
	}
	
	action disembark {
		ask owner {
				location <- target.location;
				color <- #white;
				wait <- false;
			}
	}
	
	action arrived {
		do disembark;
		do die;
	}
	
	reflex breakdown when: flip(proba_breakdown) {
		breakdown <- true;
		max_speed <- 1 #km / #h;
	}

	reflex drive when: final_target = nil and target != nil{
		do pathFind;
	}

	reflex checkArrival when: distance_to_goal = 0 and target = nil {
		do arrived;
	}

	reflex move when: current_path != nil and final_target != nil {
		do drive;
		if (final_target != nil) {
			if real_speed < 5 #km / #h {
				counter_stucked <- counter_stucked + 1;
				if (counter_stucked mod threshold_stucked = 0) {
					proba_use_linked_road <- min([1.0, proba_use_linked_road + 0.1]);
				}
	
			} else {
				counter_stucked <- 0;
				proba_use_linked_road <- 0.0;
			}
		}
		else {
			do arrived;
		}
	}

	aspect default {
		draw breakdown ? square(16) : triangle(16) color: color rotate: heading + 90;	
	}

	point calcul_loc {
		if (current_road = nil) {
			return location;
		} else {
			float val <- (road(current_road).lanes - current_lane) + 0.5;
			val <- on_linked_road ? -val : val;
			if (val = 0) {
				return location;
			} else {
				return (location + {cos(heading + 90) * val, sin(heading + 90) * val});
			}
		}
	} }
	
species bus parent: vehicle {
	rgb color <- #yellow;
	list<building> backup;
	list<building> stops;
	string route_name;
	map<people,plataform> passengers;
	
	
	action disembark {}
	
	
	action arrived {
		ask [target] of_species plataform{
			loop p over: myself.passengers.keys {
				if myself.passengers[p] = self {
					p.color <- #white;
					p.location <- self.location;
					ask p {do byFoot(target);}
					remove p from: passengers;
				}
			}
			
			loop p over: passengers.keys {
				if myself.backup contains passengers[p] {
				add (passengers at p) to: myself.passengers at: p;
				remove p from: passengers;
				p.color <- #transparent;
				}
			}
		}
		do next;
		if (target = nil) {
			stops <- copy(backup);
			do next;
		}
	}
	
	action next {
		if (!empty(stops)){
			target <- stops at 0;
			remove from: stops index: 0;
		}
		else {
			target <- nil;
		}
	}
	
	action pathFind {
		intersection real_target <- (intersection closest_to target);
		current_path <- compute_path(graph: road_network, target: real_target);
		do next;
	}
	
	
//	reflex ended when: (empty(stops) and final_target = nil){
//		do die;
//	}
	
}

//species that will represent the intersection node, it can be traffic lights or not, using the skill_road_node skill
species intersection skills: [skill_road_node] {
	bool is_traffic_signal;
	list<list> stop;
	int time_to_change <- 2;
	int counter <- rnd(time_to_change);
	list<road> ways1;
	list<road> ways2;
	bool is_green;
	rgb color_fire;

	action initialize {
		if (is_traffic_signal) {
			do compute_crossing;
			stop << [];
			if (flip(0.5)) {
				do to_green;
			} else {
				do to_red;
			}
		}
	}

	action compute_crossing {
		if (length(roads_in) >= 2) {
			road rd0 <- road(roads_in[0]);
			list<point> pts <- rd0.shape.points;
			float ref_angle <- float(last(pts) direction_to rd0.location);
			loop rd over: roads_in {
				list<point> pts2 <- road(rd).shape.points;
				float angle_dest <- float(last(pts2) direction_to rd.location);
				float ang <- abs(angle_dest - ref_angle);
				if (ang > 45 and ang < 135) or (ang > 225 and ang < 315) {
					ways2 << road(rd);
				}
			}
		}

		loop rd over: roads_in {
			if not (rd in ways2) {
				ways1 << road(rd);
			}
		}
	}

	action to_green {
		stop[0] <- ways2;
		color_fire <- #green;
		is_green <- true;
	}

	action to_red {
		stop[0] <- ways1;
		color_fire <- #red;
		is_green <- false;
	}

	reflex dynamic_node when: is_traffic_signal {
		counter <- counter + 1;
		if (counter >= time_to_change) {
			counter <- 0;
			if is_green {
				do to_red;
			} else {
				do to_green;
			}
		}
	}
	
	aspect default {
		if (is_traffic_signal) {
			draw circle(5) color: color_fire;
		}	
	}
}

species route {
	string name;
	list<plataform> stops <- [];
	
	init {
		location <- stops[0].location;
	}
}


experiment main type: gui {
	parameter "Percentage of chance to prefer bus" var: percentageToBus <- 0.29;
	parameter "Percentage of chance to prefer walking" var: percentageToWalk <- 0.30;
	parameter "Size of the Population" var: population <- 3000;
	parameter "Virus Quanta" var: virusQuanta <- 970.0;
	parameter "Representation Resolution" var: representationResolution <- 1.0;
	
	output {
		display Map type: opengl synchronized: true background: #gray{
			species building refresh:false;
			species road;
			species intersection;
			species vehicle;
			species plataform;
			species people;
			species bus;
			
		}
		
		display Info2 refresh: false autosave: true{
		chart "Distribution of Locomotion Methods" type: pie{
				data "People Walking" value: length(people where (each.method = "walk"));
				data "People Getting a Bus" value: length(people where (each.method = "bus"));
				data "People Driving" value: length(people where (each.method = "car"));
			}}
	}
}

experiment realistic type: batch until: (current_date.day=2 and current_date.hour=4){
	parameter "Percentage of chance to prefer bus" var: percentageToBus <- 0.29;
	parameter "Percentage of chance to prefer walking" var: percentageToWalk <- 0.30;
	parameter "Size of the Population" var: population <- 3000;
	
	output {
		display Info refresh: every(1#h) autosave: true{
			chart "Distribution of Locomotion Methods" type: pie{
				data "People Walking" value: length(people where (each.method = "walk"));
				data "People Getting a Bus" value: length(people where (each.method = "bus"));
				data "People Driving" value: length(people where (each.method = "car"));
			}
		
		}
	}
}

experiment TestUnit type: gui {
	parameter "Size of the Population" var: population <- 61;
	parameter "Virus Quanta" var: virusQuanta <- 970.0;
	parameter "Representation Resolution" var: representationResolution <- 1.0;
	
	output {
		display Map type: opengl synchronized: true background: #gray{
			species building refresh:false;
			species people;
			
		}
	}
}


