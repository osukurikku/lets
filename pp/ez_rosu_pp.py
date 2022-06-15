from rosu_pp_py import Calculator, ScoreParams

from common.constants import gameModes, mods
from common.log import logUtils as log
from constants import exceptions
from helpers import mapsHelper
from objects import glob
import contextlib

MODULE_NAME = "ez-rosu-pp"

stats = {
	"latency": {
		gameModes.STD: glob.stats["pp_calc_latency_seconds"].labels(game_mode="std"),
		gameModes.TAIKO: glob.stats["pp_calc_latency_seconds"].labels(game_mode="taiko"),
		gameModes.CTB: glob.stats["pp_calc_latency_seconds"].labels(game_mode="ctb"),
		gameModes.MANIA: glob.stats["pp_calc_latency_seconds"].labels(game_mode="mania")
	},
	"failures": {
		gameModes.STD: glob.stats["pp_calc_failures"].labels(game_mode="std"),
		gameModes.TAIKO: glob.stats["pp_calc_failures"].labels(game_mode="std"),
		gameModes.CTB: glob.stats["pp_calc_failures"].labels(game_mode="std"),
		gameModes.MANIA: glob.stats["pp_calc_failures"].labels(game_mode="std")
    }
}

class EzRosu:
    """
        PP calculator, based on rosu-pp-py
    """
    GAME_FOLDER = {
        gameModes.STD: ".data/oppai",
        gameModes.TAIKO: ".data/oppai",
        gameModes.CTB: ".data/catch_the_pp",
        gameModes.MANIA: ".data/omppc"
    }

    def __init__(self, beatmap_, score_=None, acc=None, mods_=None, tillerino=False, gameMode=gameModes.STD, tillerinoOnlyPP=False):
        """
            Set peace params.

            beatmap_ -- beatmap object
            score_ -- score object
            acc -- manual acc. Used in tillerino-like bot. You don't need this if you pass __score object
            mods_ -- manual mods. Used in tillerino-like bot. You don't need this if you pass __score object
            tillerino -- If True, self.pp will be a list with pp values for 100%, 99%, 98% and 95% acc. Optional.
        """
        # Default values
        self.pp = None
        self.score = None
        self.acc = 0
        self.mods = mods.NOMOD
        self.combo = -1		# FC
        self.misses = 0
        self.stars = 0
        self.tillerino = tillerino
        self.tillerinoOnlyPP = tillerinoOnlyPP

        # Beatmap object
        self.beatmap = beatmap_
        self.map = "{}.osu".format(self.beatmap.beatmapID)

         # If passed, set everything from score object
        if score_ is not None:
            self.score = score_
            self.acc = self.score.accuracy * 100
            self.mods = self.score.mods
            self.combo = self.score.maxCombo
            self.misses = self.score.cMiss
            self.gameMode = self.score.gameMode
        else:
            # Otherwise, set acc and mods from params (tillerino)
            self.acc = acc
            self.mods = mods_
            if gameMode is not None:
                self.gameMode = gameMode
            elif self.beatmap.starsStd > 0:
                self.gameMode = gameModes.STD
            elif self.beatmap.starsTaiko > 0:
                self.gameMode = gameModes.TAIKO
            elif self.beatmap.starsCtb > 0:
                self.gameMode = gameModes.CTB
            elif self.beatmap.starsMania > 0:
                self.gameMode = gameModes.MANIA
            else:
                self.gameMode = None

        # Calculate pp
        log.debug("rosu ~> Initialized rust stuff diffcalc")
        self.calculatePP()

    def _calculatePP(self):
        """
        Calculate total pp value with peace and return it

        return -- total pp
        """
        # Set variables
        self.pp = None
        peace = None
        try:
            # Check gamemode
            if self.gameMode not in (gameModes.STD, gameModes.TAIKO, gameModes.CTB, gameModes.MANIA):
                raise exceptions.unsupportedGameModeException()

            # Build .osu map file path
            mapFile = "{path}/maps/{map}".format(
                path=self.GAME_FOLDER[self.gameMode], map=self.map)
            mapsHelper.cacheMap(mapFile, self.beatmap)

            rosu = Calculator(mapFile)
            score_params = ScoreParams()

            # Not so readeable part starts here...
            if self.misses > 0:
                score_params.nMisses = self.misses
            if self.combo >= 0:
                score_params.combo = self.combo
            if not self.tillerino:
                if self.acc > 0:
                    score_params.acc = self.acc
            if self.score and self.gameMode == gameModes.MANIA:
                score_params.score = self.score.score

            if self.mods > mods.NOMOD:
                score_params.mods = self.mods
            
            [rosu_calculations] = rosu.calculate(score_params)
            if not self.tillerino:
                if rosu_calculations.mode != self.score.gameMode:
                    self.pp = 0
                else:
                    temp_pp = round(rosu_calculations.pp, 5)
                    self.stars = rosu_calculations.stars
                    if (self.gameMode == gameModes.TAIKO and self.beatmap.starsStd > 0 and temp_pp > 800) or \
                            self.stars > 50 or \
                                self.gameMode == gameModes.MANIA and self.mods & mods.SCOREV2 > 0:
                        # Invalidate pp for bugged taiko converteds and bugged inf pp std maps
                        self.pp = 0
                    else:
                        self.pp = temp_pp
            else:
                if rosu_calculations.mode != self.score.gameMode:
                    self.pp = [0, 0, 0, 0]
                else:
                    pp_list = []
                    self.stars = rosu_calculations.stars

                    if self.acc and self.acc > 0:
                        score_params.acc = self.acc
                        [rosu_calculations] = rosu.calculate(score_params)

                        self.pp = rosu_calculations.pp
                    else:
                        # ik that can be a better way, but i don't wanna do something "NICE" to this odd code
                        for acc in (100, 99, 98, 95):
                            score_params.acc = self.acc
                            [rosu_calculations] = rosu.calculate(score_params)
                            pp = round(rosu_calculations.pp, 5)
                            # If this is a broken converted, set all pp to 0 and break the loop
                            if self.gameMode == gameModes.TAIKO and self.beatmap.starsStd > 0 and pp > 800 or \
                                self.gameMode == gameModes.MANIA and self.mods & mods.SCOREV2 > 0:
                                pp_list = [0, 0, 0, 0]
                                break

                            pp_list.append(pp)

                        self.pp = pp_list

            log.debug("rosu ~> Calculated PP: {}, stars: {}".format(
                self.pp, self.stars))
        except exceptions.osuApiFailException:
            log.error("rosu ~> osu!api error!")
            self.pp = 0
        except exceptions.unsupportedGameModeException:
            log.error("rosu ~> Unsupported gamemode")
            self.pp = 0
        except Exception as e:
            log.error("rosu ~> Unhandled exception: {}".format(str(e)))
            self.pp = 0
            raise
        finally:
            log.debug("rosu ~> Shutting down, pp = {}".format(self.pp))

    def calculatePP(self):
        latencyCtx = contextlib.suppress()
        excC = None
        if not self.tillerino and self.score.gameMode:
            latencyCtx = stats["latency"][self.score.gameMode].time()
            excC = stats["failures"][self.score.gameMode]

        with latencyCtx:
            try:
                return self._calculatePP()
            finally:
                if not self.tillerino and self.pp <= 0 and excC is not None:
                    excC.inc()
