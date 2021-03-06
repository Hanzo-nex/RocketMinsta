//EF_BRIGHTFIELD|EF_BRIGHTLIGHT|EF_DIMLIGHT|EF_BLUE|EF_RED|EF_FLAME
#define BALL_EFFECTMASK 1229
#define BALL_MINS '-16 -16 -16'  // The model is 24*24*24
#define BALL_MAXS '16 16 16'
#define BALL_ATTACHORG '3 0 16'
#define BALL_SPRITECOLOR '.91 .85 .62'
#define BALL_FOOT   1
#define BALL_BASKET 2
//spawnflags
#define GOAL_TOUCHPLAYER 1
//goal types
#define GOAL_FAULT -1
#define GOAL_OUT -2

#define CVTOV(s) s = cvar( #s )

float g_nexball_football_boost_forward;
float g_nexball_football_boost_up;
float g_nexball_football_physics;
float g_nexball_delay_idle;
float g_nexball_basketball_delay_hold;
float g_nexball_basketball_delay_hold_forteam;
float g_nexball_basketball_effects_default;
float g_nexball_basketball_teamsteal;
float balls;
float ball_scale;
float nb_teams;

.float teamtime;

void nb_delayedinit();
void nb_init() // Called early (worldspawn stage)
{
	CVTOV(g_nexball_meter_period); //sent with the client init entity
	if (g_nexball_meter_period <= 0)
		g_nexball_meter_period = 2; // avoid division by zero etc. due to silly users
	g_nexball_meter_period = rint(g_nexball_meter_period * 32) / 32; //Round to 1/32ths to send as a byte multiplied by 32
	addstat(STAT_NB_METERSTART, AS_FLOAT, metertime);

	// General settings
	CVTOV(g_nexball_football_boost_forward);   //100
	CVTOV(g_nexball_football_boost_up);        //200
	CVTOV(g_nexball_delay_idle);               //10
	CVTOV(g_nexball_football_physics);         //0

	radar_showennemies = cvar("g_nexball_radar_showallplayers");

	InitializeEntity(world, nb_delayedinit, INITPRIO_GAMETYPE);
}

float OtherTeam(float t)  //works only if there are two teams on the map!
{
	entity e;
	e = find(world, classname, "nexball_team");
	if (e.team == t)
		e = find(e, classname, "nexball_team");
	return e.team;
}

void ResetBall();

void LogNB(string mode, entity actor)
{
	string s;
	if(!cvar("sv_eventlog"))
		return;
	s = strcat(":nexball:", mode);
	if(actor != world)
		s = strcat(s, ":", ftos(actor.playerid));
	GameLogEcho(s);
}

void ball_restart (void)
{
	if(self.owner)
		DropBall(self, self.owner.origin, '0 0 0');
	ResetBall();
}

void nexball_setstatus (void)
{
	local entity oldself;
	if (!g_nexball)
		return;
	if (self.ballcarried)
	{
		if (self.ballcarried.teamtime && (self.ballcarried.teamtime < time))
		{
			bprint("The ", ColoredTeamName(self.team), " held the ball for too long.\n");
			oldself = self;
			self = self.ballcarried;
			DropBall(self, self.owner.origin, '0 0 0');
			ResetBall();
			self = oldself;
		} else
			self.items |= IT_KEY1;
	}
}

void relocate_nexball (void)
{
	tracebox(self.origin, BALL_MINS, BALL_MAXS, self.origin, TRUE, self);
	if (trace_startsolid)
	{
		vector o;
		o = self.origin;
		if(!move_out_of_solid(self))
			objerror("could not get out of solid at all!");
		print("^1NOTE: this map needs FIXING. ", self.classname, " at ", vtos(o - '0 0 1'));
		print(" needs to be moved out of solid, e.g. by '", ftos(self.origin_x - o_x));
		print(" ", ftos(self.origin_y - o_y));
		print(" ", ftos(self.origin_z - o_z), "'\n");
		self.origin = o;
	}
}

void basketball_touch();
void football_touch();

void DropOwner (void)
{
	local entity ownr;
	ownr = self.owner;
	DropBall(self, ownr.origin, ownr.velocity);
	makevectors(ownr.v_angle_y * '0 1 0');
	ownr.velocity += ('0 0 0.75' - v_forward) * 1000;
	ownr.flags &~= FL_ONGROUND;
}

void GiveBall (entity plyr, entity ball)
{
	local entity ownr;

	if ((ownr = ball.owner))
	{
		ownr.effects &~= g_nexball_basketball_effects_default;
		ownr.ballcarried = world;
		if (ownr.metertime)
		{
			ownr.metertime = 0;
			ownr.weaponentity.state = WS_READY;
		}
		WaypointSprite_Kill(ownr.waypointsprite_attachedforcarrier);
	}
	else
	{
		WaypointSprite_Kill(ball.waypointsprite_attachedforcarrier);
	}

	setattachment(ball, plyr, "");
	setorigin(ball, BALL_ATTACHORG);

	if (ball.team != plyr.team)
		ball.teamtime = time + g_nexball_basketball_delay_hold_forteam;

	ball.owner = ball.pusher = plyr; //"owner" is set to the player carrying, "pusher" to the last player who touched it
	ball.team = plyr.team;
	plyr.ballcarried = ball;
	ball.dropperid = plyr.playerid;

	plyr.effects |= g_nexball_basketball_effects_default;
	ball.effects &~= g_nexball_basketball_effects_default;

	ball.velocity = '0 0 0';
	ball.movetype = MOVETYPE_NONE;
	ball.touch = SUB_Null;
	ball.effects |= EF_NOSHADOW;
	ball.scale = 1; // scale down.

	WaypointSprite_AttachCarrier("nb-ball", plyr);
	WaypointSprite_UpdateRule(plyr.waypointsprite_attachedforcarrier, 0, SPRITERULE_DEFAULT);
	WaypointSprite_UpdateTeamRadar(plyr.waypointsprite_attachedforcarrier, RADARICON_FLAGCARRIER, BALL_SPRITECOLOR);

	if (g_nexball_basketball_delay_hold)
	{
		ball.think = DropOwner;
		ball.nextthink = time + g_nexball_basketball_delay_hold;
	}
}

void DropBall (entity ball, vector org, vector vel)
{
	ball.effects |= g_nexball_basketball_effects_default;
	ball.effects &~= EF_NOSHADOW;
	ball.owner.effects &~= g_nexball_basketball_effects_default;

	setattachment(ball, world, "");
	setorigin (ball, org);
	ball.movetype = MOVETYPE_BOUNCE;
	ball.flags &~= FL_ONGROUND;
	ball.scale = ball_scale;
	ball.velocity = vel;
	ball.ctf_droptime = time;
	ball.touch = basketball_touch;
	ball.think = ResetBall;
	ball.nextthink = min(time + g_nexball_delay_idle, ball.teamtime);

	if (ball.owner.metertime)
	{
		ball.owner.metertime = 0;
		ball.owner.weaponentity.state = WS_READY;
	}

	WaypointSprite_Kill(ball.owner.waypointsprite_attachedforcarrier);
	WaypointSprite_AttachCarrier("nb-ball", ball);
	WaypointSprite_UpdateRule(ball.waypointsprite_attachedforcarrier, 0, SPRITERULE_DEFAULT);
	WaypointSprite_UpdateTeamRadar(ball.waypointsprite_attachedforcarrier, RADARICON_FLAGCARRIER, BALL_SPRITECOLOR);

	ball.owner.ballcarried = world;
	ball.owner = world;
}

void InitBall (void)
{
	if (gameover) return;
	self.flags &~= FL_ONGROUND;
	self.movetype = MOVETYPE_BOUNCE;
	if (self.classname == "nexball_basketball")
		self.touch = basketball_touch;
	else if (self.classname == "nexball_football")
		self.touch = football_touch;
	self.cnt = 0;
	self.think = ResetBall;
	self.nextthink = time + g_nexball_delay_idle + 3;
	self.teamtime = 0;
	self.pusher = world;
	self.team = FALSE;
	sound (self, CHAN_PROJECTILE, self.noise1, VOL_BASE, ATTN_NORM);
	WaypointSprite_Ping(self.waypointsprite_attachedforcarrier);
	LogNB("init", world);
}

void ResetBall (void)
{
	if (self.cnt < 2) { // step 1
		if (time == self.teamtime)
			bprint("The ", ColoredTeamName(self.team), " held the ball for too long.\n");
		self.touch = SUB_Null;
		self.movetype = MOVETYPE_NOCLIP;
		self.velocity = '0 0 0'; // just in case?
		if(!self.cnt)
			LogNB("resetidle", world);
		self.cnt = 2;
		self.nextthink = time;
	} else if (self.cnt < 4) { // step 2 and 3
//		dprint("Step ", ftos(self.cnt), ": Calculated velocity: ", vtos(self.spawnorigin - self.origin), ", time: ", ftos(time), "\n");
		self.velocity = (self.spawnorigin - self.origin) * (self.cnt - 1); // 1 or 0.5 second movement
		self.nextthink = time + 0.5;
		self.cnt += 1;
	} else { // step 4
//		dprint("Step 4: time: ", ftos(time), "\n");
		if (vlen(self.origin - self.spawnorigin) > 10) // should not happen anymore
			dprint("The ball moved too far away from its spawn origin.\nOffset: ",
			       vtos(self.origin - self.spawnorigin), " Velocity: ", vtos(self.velocity), "\n");
		self.velocity = '0 0 0';
		setorigin(self, self.spawnorigin); // make sure it's positioned correctly anyway
		self.movetype = MOVETYPE_NONE;
		self.think = InitBall;
		self.nextthink = max(time, game_starttime) + cvar("g_nexball_delay_start");
	}
}

void football_touch (void)
{
	if (other.solid == SOLID_BSP) {
		if (time > self.lastground + 0.1)
		{
			sound (self, CHAN_PROJECTILE, self.noise, VOL_BASE, ATTN_NORM);
			self.lastground = time;
		}
		if (vlen(self.velocity) && !self.cnt)
			self.nextthink = time + g_nexball_delay_idle;
		return;
	}
	if (other.classname != "player")
		return;
	if (other.health < 1)
		return;
	if (!self.cnt)
		self.nextthink = time + g_nexball_delay_idle;

	self.pusher = other;
	self.team = other.team;

	if (g_nexball_football_physics == -1) { // MrBougo try 1, before decompiling Rev's original
		if (vlen(other.velocity))
			self.velocity = other.velocity * 1.5 + '0 0 1' * g_nexball_football_boost_up;
	} else if (g_nexball_football_physics == 1) { // MrBougo's modded Rev style: partially independant of the height of the aiming point
		makevectors(other.v_angle);
		self.velocity = other.velocity + v_forward * g_nexball_football_boost_forward + '0 0 1' * g_nexball_football_boost_up;
	} else if (g_nexball_football_physics == 2) { // 2nd mod try: totally independant. Really playable!
		makevectors(other.v_angle_y * '0 1 0');
		self.velocity = other.velocity + v_forward * g_nexball_football_boost_forward + v_up * g_nexball_football_boost_up;
	} else { // Revenant's original style (from the original mod's disassembly, acknowledged by Revenant)
		makevectors(other.v_angle);
		self.velocity = other.velocity + v_forward * g_nexball_football_boost_forward + v_up * g_nexball_football_boost_up;
	}
	self.avelocity = -250 * v_forward;  // maybe there is a way to make it look better?
}

void basketball_touch (void)
{
	if (other.ballcarried)
	{
		football_touch();
		return;
	}
	if (!self.cnt && other.classname == "player" && (other.playerid != self.dropperid || time > self.ctf_droptime + cvar("g_nexball_delay_collect"))) {
		if (other.health <= 0)
			return;
		LogNB("caught", other);
		GiveBall(other, self);
	} else if (other.solid == SOLID_BSP) {
		sound (self, CHAN_PROJECTILE, self.noise, VOL_BASE, ATTN_NORM);
		if (vlen(self.velocity) && !self.cnt)
			self.nextthink = min(time + g_nexball_delay_idle, self.teamtime);
	}
}

void GoalTouch (void)
{
	entity ball;
	float isclient, pscore, otherteam;
	string pname;

	if (gameover) return;
	if ((self.spawnflags & GOAL_TOUCHPLAYER) && other.ballcarried)
		ball = other.ballcarried;
	else
		ball = other;
	if (ball.classname != "nexball_basketball")
	if (ball.classname != "nexball_football")
		return;
	if ((!ball.pusher && self.team != GOAL_OUT) || ball.cnt)
		return;
	EXACTTRIGGER_TOUCH;


	if(nb_teams == 2)
		otherteam = OtherTeam(ball.team);

	if((isclient = ball.pusher.flags & FL_CLIENT))
		pname = ball.pusher.netname;
	else
		pname = "Someone (?)";

	if        (ball.team == self.team) //owngoal (regular goals)
	{
		LogNB("owngoal", ball.pusher);
		bprint("Boo! ", pname, "^7 scored a goal against his own team!\n");
		pscore = -1;
	} else if (self.team == GOAL_FAULT) {
		LogNB("fault", ball.pusher);
		if (nb_teams == 2)
			bprint(ColoredTeamName(otherteam), " gets a point due to ", pname, "^7's silliness.\n");
		else
			bprint(ColoredTeamName(ball.team), " loses a point due to ", pname, "^7's silliness.\n");
		pscore = -1;
	} else if (self.team == GOAL_OUT) {
		LogNB("out", ball.pusher);
		if ((self.spawnflags & GOAL_TOUCHPLAYER) && ball.owner)
			bprint(pname, "^7 went out of bounds.\n");
		else
			bprint("The ball was returned.\n");
		pscore = 0;
	} else {                           //score
		LogNB(strcat("goal:", ftos(self.team)), ball.pusher);
		bprint("Goaaaaal! ", pname, "^7 scored a point for the ", ColoredTeamName(ball.team), ".\n");
		pscore = 1;
	}

	sound (ball, CHAN_AUTO, self.noise, VOL_BASE, ATTN_NONE);

	if(ball.team && pscore)
	{
		if (nb_teams == 2 && pscore < 0)
			TeamScore_AddToTeam(otherteam, ST_NEXBALL_GOALS, -pscore);
		else
			TeamScore_AddToTeam(ball.team, ST_NEXBALL_GOALS, pscore);
	}
	if (isclient)
	{
		if (pscore > 0)
			PlayerScore_Add(ball.pusher, SP_NEXBALL_GOALS, pscore);
		else if (pscore < 0)
			PlayerScore_Add(ball.pusher, SP_NEXBALL_FAULTS, -pscore);
	}

	if (ball.owner) // Happens on spawnflag GOAL_TOUCHPLAYER
		DropBall(ball, ball.owner.origin, ball.owner.velocity);

	WaypointSprite_Ping(ball.waypointsprite_attachedforcarrier);

	ball.cnt = 1;
	ball.think = ResetBall;
	if (ball.classname == "nexball_basketball")
		ball.touch = football_touch; // better than SUB_Null: football control until the ball gets reset
	ball.nextthink = time + cvar("g_nexball_delay_goal") * (self.team != GOAL_OUT);
}

//=======================//
//       team ents       //
//=======================//
void spawnfunc_nexball_team (void)
{
	if(!g_nexball) { remove(self); return; }
	self.team = self.cnt + 1;
}

void nb_spawnteam (string teamname, float teamcolor)
{
	dprint("^2spawned team ", teamname, "\n");
	local entity e;
	e = spawn();
	e.classname = "nexball_team";
	e.netname = teamname;
	e.cnt = teamcolor;
	e.team = e.cnt + 1;
	nb_teams += 1;
};

void nb_spawnteams (void)
{
	float t_r, t_b, t_y, t_p;
	entity e;
	for(e = world; (e = find(e, classname, "nexball_goal")); )
	{
		switch(e.team)
		{
			case COLOR_TEAM1: if(!t_r) { nb_spawnteam ("Red", e.team-1)   ; t_r = 1; } break;
			case COLOR_TEAM2: if(!t_b) { nb_spawnteam ("Blue", e.team-1)  ; t_b = 1; } break;
			case COLOR_TEAM3: if(!t_y) { nb_spawnteam ("Yellow", e.team-1); t_y = 1; } break;
			case COLOR_TEAM4: if(!t_p) { nb_spawnteam ("Pink", e.team-1)  ; t_p = 1; } break;
		}
	}
}

void nb_delayedinit (void)
{
	if (find(world, classname, "nexball_team") == world)
		nb_spawnteams();
	ScoreRules_nexball(nb_teams);
}


//=======================//
//      spawnfuncs       //
//=======================//

void SpawnBall (void)
{
	if(!g_nexball) { remove(self); return; }

//	balls += 4; // using the remaining bits to count balls will leave more than the max edict count, so it's fine

	if (!self.model) {
		self.model = "models/nexball/ball.md3";
		self.scale = 1.3;
	}

	precache_model (self.model);
	setmodel (self, self.model);
	setsize (self, BALL_MINS, BALL_MAXS);
	ball_scale = self.scale;

	relocate_nexball();
	self.spawnorigin = self.origin;

	self.effects = self.effects | EF_LOWPRECISION;

	if (cvar(strcat("g_", self.classname, "_trail"))) //nexball_basketball :p
	{
		self.glow_color = cvar("g_nexball_trail_color");
		self.glow_trail = TRUE;
	}

	self.movetype = MOVETYPE_FLY;

	if (!cvar("g_nexball_sound_bounce"))
		self.noise = "";
	else if (!self.noise)
		self.noise = "sound/nexball/bounce.wav";
		//bounce sound placeholder (FIXME)
	if (!self.noise1)
		self.noise1 = "sound/nexball/drop.wav";
		//ball drop sound placeholder (FIXME)
	if (!self.noise2)
		self.noise2 = "sound/nexball/steal.wav";
		//stealing sound placeholder (FIXME)
	if (self.noise) precache_sound (self.noise);
	precache_sound (self.noise1);
	precache_sound (self.noise2);

	WaypointSprite_AttachCarrier("nb-ball", self); // the ball's team is not set yet, no rule update needed
	WaypointSprite_UpdateTeamRadar(self.waypointsprite_attachedforcarrier, RADARICON_FLAGCARRIER, BALL_SPRITECOLOR);

	self.reset = ball_restart;
	self.think = InitBall;
	self.nextthink = game_starttime + cvar("g_nexball_delay_start");
}

void spawnfunc_nexball_basketball (void)
{
	self.classname = "nexball_basketball";
	if not(balls & BALL_BASKET)
	{
		CVTOV(g_nexball_basketball_effects_default);
		CVTOV(g_nexball_basketball_delay_hold);
		CVTOV(g_nexball_basketball_delay_hold_forteam);
		CVTOV(g_nexball_basketball_teamsteal);
		g_nexball_basketball_effects_default = g_nexball_basketball_effects_default & BALL_EFFECTMASK;
	}
	if (!self.effects)
		self.effects = g_nexball_basketball_effects_default;
	self.solid = SOLID_TRIGGER;
	balls |= BALL_BASKET;
	self.bouncefactor = cvar("g_nexball_basketball_bouncefactor");
	self.bouncestop = cvar("g_nexball_basketball_bouncestop");
	SpawnBall();
}

void spawnfunc_nexball_football (void)
{
	self.classname = "nexball_football";
	self.solid = SOLID_TRIGGER;
	balls |= BALL_FOOT;
	self.bouncefactor = cvar("g_nexball_football_bouncefactor");
	self.bouncestop = cvar("g_nexball_football_bouncestop");
	SpawnBall();
}

void SpawnGoal (void)
{
	if(!g_nexball) { remove(self); return; }
	EXACTTRIGGER_INIT;
	self.classname = "nexball_goal";
	if (!self.noise)
		self.noise = "ctf/respawn.wav";
	precache_sound(self.noise);
	self.touch = GoalTouch;
}

void spawnfunc_nexball_redgoal (void)
{
	self.team = COLOR_TEAM1;
	SpawnGoal();
}
void spawnfunc_nexball_bluegoal (void)
{
	self.team = COLOR_TEAM2;
	SpawnGoal();
}
void spawnfunc_nexball_yellowgoal (void)
{
	self.team = COLOR_TEAM3;
	SpawnGoal();
}
void spawnfunc_nexball_pinkgoal (void)
{
	self.team = COLOR_TEAM4;
	SpawnGoal();
}

void spawnfunc_nexball_fault (void)
{
	self.team = GOAL_FAULT;
	if (!self.noise)
		self.noise = "misc/typehit.wav";
	SpawnGoal();
}

void spawnfunc_nexball_out (void)
{
	self.team = GOAL_OUT;
	if (!self.noise)
		self.noise = "misc/typehit.wav";
	SpawnGoal();
}

//
//Spawnfuncs preserved for compatibility
//

void spawnfunc_ball            (void) { spawnfunc_nexball_football(); }
void spawnfunc_ball_football   (void) { spawnfunc_nexball_football(); }
void spawnfunc_ball_basketball (void) { spawnfunc_nexball_basketball(); }
// The "red goal" is defended by blue team. A ball in there counts as a point for red.
void spawnfunc_ball_redgoal    (void) { spawnfunc_nexball_bluegoal(); } // I blame Revenant
void spawnfunc_ball_bluegoal   (void) { spawnfunc_nexball_redgoal(); }  // but he didn't mean to cause trouble :p
void spawnfunc_ball_fault      (void) { spawnfunc_nexball_fault(); }
void spawnfunc_ball_bound      (void) { spawnfunc_nexball_out(); }

//=======================//
//      Weapon code      //
//=======================//

void W_Nexball_Touch (void)
{
	local entity ball, attacker;
	attacker = self.owner;

	PROJECTILE_TOUCH;
	if(attacker.team != other.team || g_nexball_basketball_teamsteal)
	if((ball = other.ballcarried) && (attacker.classname == "player" || attacker.classname == "gib"))
	{
		other.velocity = other.velocity + normalize(self.velocity) * other.damageforcescale * cvar("g_balance_nexball_secondary_force");
		other.flags &~= FL_ONGROUND;
		if(!attacker.ballcarried)
		{
			LogNB("stole", attacker);
			sound (other, CHAN_AUTO, ball.noise2, VOL_BASE, ATTN_NORM);

			if(attacker.team == other.team && time > attacker.teamkill_complain)
			{
				attacker.teamkill_complain = time + 5;
				attacker.teamkill_soundtime = time + 0.4;
				attacker.teamkill_soundsource = other;
			}

			GiveBall(attacker, other.ballcarried);
		}
	}
	remove(self);
}

void W_Nexball_Attack (float t)
{
	local entity ball;
	local float mul, mi, ma;
	if (!(ball = self.ballcarried))
		return;

	W_SetupShot (self, FALSE, 4, "nexball/shoot1.wav",0);
	tracebox(w_shotorg, BALL_MINS, BALL_MAXS, w_shotorg, MOVE_WORLDONLY, world);
	if(trace_startsolid)
	{
		if(self.metertime)
			self.metertime = 0; // Shot failed, hide the power meter
		return;
	}

	//Calculate multiplier
	if (t < 0)
		mul = 1;
	else
	{
		mi = cvar("g_nexball_basketball_meter_minpower");
		ma = max(mi, cvar("g_nexball_basketball_meter_maxpower")); // avoid confusion
		//One triangle wave period with 1 as max
		mul = 2 * mod(t, g_nexball_meter_period) / g_nexball_meter_period;
		if (mul > 1)
			mul = 2 - mul;
		mul = mi + (ma - mi) * mul; // range from the minimal power to the maximal power
	}
	DropBall (ball, w_shotorg, W_CalculateProjectileVelocity(self.velocity, w_shotdir * cvar("g_balance_nexball_primary_speed") * mul));
	//TODO: use the speed_up cvar too ??
}

void W_Nexball_Attack2 (void)
{
	local entity missile;
	if (!(balls & BALL_BASKET))
		return;
	W_SetupShot (self, FALSE, 2, "nexball/shoot2.wav",0);
//	pointparticles(particleeffectnum("grenadelauncher_muzzleflash"), w_shotorg, w_shotdir * 1000, 1);
	missile = spawn ();

	missile.owner = self;
	missile.classname = "ballstealer";

	missile.movetype = MOVETYPE_FLY;
	PROJECTILE_MAKETRIGGER(missile);

	setmodel (missile, "models/elaser.mdl"); // precision set below
	setsize (missile, '0 0 0', '0 0 0');
	setorigin (missile, w_shotorg);

	missile.velocity = w_shotdir * cvar("g_balance_nexball_secondary_speed");
	W_SetupProjectileVelocity(missile);
	missile.angles = vectoangles (missile.velocity);
	missile.touch = W_Nexball_Touch;
	missile.think = SUB_Remove;
	missile.nextthink = time + cvar("g_balance_nexball_secondary_lifetime"); //FIXME: use a distance instead?

	missile.effects = EF_BRIGHTFIELD | EF_LOWPRECISION;
	missile.flags = FL_PROJECTILE;
}

float w_nexball_weapon(float req)
{
	if (req == WR_THINK)
	{
		if (self.BUTTON_ATCK)
		if (weapon_prepareattack(0, cvar("g_balance_nexball_primary_refire")))
		if (cvar("g_nexball_basketball_meter"))
		{
			if (self.ballcarried && !self.metertime)
				self.metertime = time;
			else
				weapon_thinkf(WFRAME_FIRE1, cvar("g_balance_nexball_primary_animtime"), w_ready);
		}
		else
		{
			W_Nexball_Attack(-1);
			weapon_thinkf(WFRAME_FIRE1, cvar("g_balance_nexball_primary_animtime"), w_ready);
		}
		if (self.BUTTON_ATCK2)
		if (weapon_prepareattack(1, cvar("g_balance_nexball_secondary_refire")))
		{
			W_Nexball_Attack2();
			weapon_thinkf(WFRAME_FIRE2, cvar("g_balance_nexball_secondary_animtime"), w_ready);
		}

		if (!self.BUTTON_ATCK && self.metertime && self.ballcarried)
		{
			W_Nexball_Attack(time - self.metertime);
			// DropBall or stealing will set metertime back to 0
			weapon_thinkf(WFRAME_FIRE1, cvar("g_balance_nexball_primary_animtime"), w_ready);
		}
	}
	else if (req == WR_PRECACHE)
	{
		precache_model ("models/weapons/g_porto.md3");
		precache_model ("models/weapons/v_porto.md3");
		precache_model ("models/weapons/h_porto.dpm");
		precache_model ("models/elaser.mdl");
		precache_sound ("nexball/shoot1.wav");
		precache_sound ("nexball/shoot2.wav");
	}
	else if (req == WR_SETUP)
		weapon_setup(WEP_PORTO);
	else if (req == WR_SUICIDEMESSAGE)
	{
		w_deathtypestring = "is a weirdo";
	}
	else if (req == WR_KILLMESSAGE)
	{
		w_deathtypestring = "got killed by #'s black magic";
	}
	// No need to check WR_CHECKAMMO* or WR_AIM, it should always return TRUE
	return TRUE;
}
