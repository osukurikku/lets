import time

import pp
from pp import ez_peace
from common.constants import gameModes
from common.constants import mods as PlayMods
from objects import beatmap
from common.log import logUtils as log
from common.ripple import userUtils
from common.ripple import scoreUtils
from objects import glob
from constants import rankedStatuses
from common import generalUtils
from helpers import kotrikhelper


class score:
	__slots__ = ("scoreID", "playerName", "score", "maxCombo", "c50", "c100", "c300", "cMiss", "cKatu", "cGeki",
	             "fullCombo", "mods", "playerUserID","rank","date", "hasReplay", "fileMd5", "passed", "playDateTime",
	             "gameMode", "completed", "accuracy", "pp", "sr", "oldPersonalBest", "rankedScoreIncrease", "clan", "personalOldBestScore", "playTime", "scoreHash",
				 "quit", "failed")
	def __init__(self, scoreID = None, rank = None, setData = True):
		"""
		Initialize a (empty) score object.
		scoreID -- score ID, used to get score data from db. Optional.
		rank -- score rank. Optional
		setData -- if True, set score data from db using scoreID. Optional.
		"""
		self.scoreID = 0
		self.scoreHash = ''
		self.playerName = "nospe"
		self.score = 0
		self.maxCombo = 0
		self.c50 = 0
		self.c100 = 0
		self.c300 = 0
		self.cMiss = 0
		self.cKatu = 0
		self.cGeki = 0
		self.fullCombo = False
		self.mods = 0
		self.playerUserID = 0
		self.rank = rank	# can be empty string too
		self.date = 0
		self.hasReplay = 0

		self.fileMd5 = None
		self.passed = False
		self.playDateTime = 0
		self.gameMode = 0
		self.completed = 0
		self.playTime = 0 # I will make this only for completed scores with completed flag == 3, I really don't want store failed scores, sry buddies, my ssd is not unlimited(

		self.accuracy = 0.00
		self.clan = 0

		self.pp = 0.00
		self.sr = 0

		self.oldPersonalBest = 0
		self.rankedScoreIncrease = 0
		self.personalOldBestScore = None

		if scoreID is not None and setData:
			self.setDataFromDB(scoreID, rank)

	def calculateAccuracy(self):
		"""
		Calculate and set accuracy for that score
		"""
		if self.gameMode == 0:
			# std
			totalPoints = self.c50*50+self.c100*100+self.c300*300
			totalHits = self.c300+self.c100+self.c50+self.cMiss
			if totalHits == 0:
				self.accuracy = 1
			else:
				self.accuracy = totalPoints/(totalHits*300)
		elif self.gameMode == 1:
			# taiko
			totalPoints = (self.c100*50)+(self.c300*100)
			totalHits = self.cMiss+self.c100+self.c300
			if totalHits == 0:
				self.accuracy = 1
			else:
				self.accuracy = totalPoints / (totalHits * 100)
		elif self.gameMode == 2:
			# ctb
			fruits = self.c300+self.c100+self.c50
			totalFruits = fruits+self.cMiss+self.cKatu
			if totalFruits == 0:
				self.accuracy = 1
			else:
				self.accuracy = fruits / totalFruits
		elif self.gameMode == 3:
			# mania
			totalPoints = self.c50*50+self.c100*100+self.cKatu*200+self.c300*300+self.cGeki*300
			totalHits = self.cMiss+self.c50+self.c100+self.c300+self.cGeki+self.cKatu
			self.accuracy = totalPoints / (totalHits * 300)
		else:
			# unknown gamemode
			self.accuracy = 0

	def setRank(self, rank):
		"""
		Force a score rank
		rank -- new score rank
		"""
		self.rank = rank
		
	def calculatePlayTime(self, normalPlayTime = None, failTime = None):
		def __adjustSeconds(x):
			return x // 1.5 if (self.mods & PlayMods.DOUBLETIME) > 0 else x // 0.75 if (self.mods & PlayMods.HALFTIME) > 0 else x

		normalPlayTime = __adjustSeconds(normalPlayTime)
		if not failTime:
			# its a normal using of this
			self.playTime = normalPlayTime
			return
		
		# if failtime presented
		failedPlayTime = __adjustSeconds(failTime)
		if normalPlayTime and failedPlayTime > normalPlayTime * 1.33:
			self.playTime = 0
			return
		
		self.playTime = failedPlayTime
		return

	def setDataFromDB(self, scoreID, rank = None):
		"""
		Set this object's score data from db
		Sets playerUserID too
		scoreID -- score ID
		rank -- rank in scoreboard. Optional.
		"""
		data = glob.db.fetch("SELECT scores.*, users.username FROM scores LEFT JOIN users ON users.id = scores.userid WHERE scores.id = %s LIMIT 1", [scoreID])
		if data is not None:
			self.setDataFromDict(data, rank)

	def setDataFromDict(self, data, rank = None):
		"""
		Set this object's score data from dictionary
		Doesn't set playerUserID
		data -- score dictionarty
		rank -- rank in scoreboard. Optional.
		"""
		#print(str(data))
		self.scoreID = data["id"]
		self.playerName = userUtils.getUsername(data["userid"])
		self.playerUserID = data["userid"]
		self.score = data["score"]
		self.maxCombo = data["max_combo"]
		self.gameMode = data["play_mode"]
		self.c50 = data["50_count"]
		self.c100 = data["100_count"]
		self.c300 = data["300_count"]
		self.cMiss = data["misses_count"]
		self.cKatu = data["katus_count"]
		self.cGeki = data["gekis_count"]
		self.fullCombo = True if data["full_combo"] == 1 else False
		self.mods = data["mods"]
		self.rank = rank if rank is not None else ""
		self.date = data["time"]
		self.fileMd5 = data["beatmap_md5"]
		self.completed = data["completed"]
		#if "pp" in data:
		self.pp = data["pp"]
		self.calculateAccuracy()

	# I don't want some break, that's why I made this method ;d
	def setClanDataFromDict(self, data, rank = None):
		"""
		Set this object's score data from dictionary
		Doesn't set playerUserID
		data -- score dictionarty
		rank -- rank in scoreboard. Optional.
		"""
		#print(str(data))
		self.scoreID = 0
		self.playerName = f"[{data['clan_tag']}] {data['clan_name']}"
		self.playerUserID = 2000000000+data['clan']
		self.score = data["score"]
		self.maxCombo = data["max_combo"]
		self.gameMode = data["play_mode"]
		self.c50 = data["50_count"]
		self.c100 = data["100_count"]
		self.c300 = data["300_count"]
		self.cMiss = data["misses_count"]
		self.cKatu = data["katus_count"]
		self.cGeki = data["gekis_count"]
		self.fullCombo = True if data["full_combo"] == 1 else False
		self.mods = 0
		self.rank = rank if rank is not None else ""
		self.date = data["time"]
		self.fileMd5 = data["beatmap_md5"]
		self.completed = data["completed"]
		#if "pp" in data:
		self.pp = int(data["pp"]/2)
		self.clan = data['clan']
		self.calculateAccuracy()

	def reSetClanDataFromScoreObject(self, new_data):
		self.score = self.score+new_data['score']
		self.maxCombo = self.maxCombo if new_data['max_combo'] <= self.maxCombo else new_data['max_combo']
		self.c50 = self.c50+new_data['50_count']
		self.c100 = self.c100+new_data['100_count']
		self.c300 = self.c300+new_data['300_count']
		self.cMiss = self.cMiss+new_data['misses_count']
		self.cKatu = self.cKatu+new_data['katus_count']
		self.cGeki = self.cGeki+new_data['gekis_count']
		self.fullCombo = True if new_data["full_combo"] == 1 else False
		self.mods = 0
		self.rank = self.rank if self.rank is not None else ""
		self.date = new_data["time"] if self.date<new_data['time'] else self.date
		#if "pp" in data:
		self.pp = int((self.pp+new_data['pp'])/2)
		self.calculateAccuracy()

	def setDataFromScoreData(self, scoreData, scoreHash: str = '', leaved: bool = False, failed: bool = False):
		"""
		Set this object's score data from scoreData list (submit modular)
		scoreData -- scoreData list
		"""
		if len(scoreData) >= 16:
			self.fileMd5 = scoreData[0]
			self.playerName = scoreData[1].strip()
			# %s%s%s = scoreData[2]
			self.c300 = int(scoreData[3])
			self.c100 = int(scoreData[4])
			self.c50 = int(scoreData[5])
			self.cGeki = int(scoreData[6])
			self.cKatu = int(scoreData[7])
			self.cMiss = int(scoreData[8])
			self.score = int(scoreData[9])
			self.maxCombo = int(scoreData[10])
			self.fullCombo = scoreData[11] == 'True'
			self.rank = scoreData[12]
			self.mods = int(scoreData[13])
			self.passed = scoreData[14] == 'True'
			self.gameMode = int(scoreData[15])
			#self.playDateTime = int(scoreData[16])
			self.playDateTime = int(time.time())
			self.calculateAccuracy()
			self.scoreHash = scoreHash
			self.quit = leaved
			self.failed = failed
			#osuVersion = scoreData[17]

			# Set completed status
			#self.setCompletedStatus()


	def getData(self, pp=False):
		"""Return score row relative to this score for getscores"""
		return "{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|1\n".format(
			self.scoreID,
			self.playerName,
			int(self.pp) if pp else self.score,
			self.maxCombo,
			self.c50,
			self.c100,
			self.c300,
			self.cMiss,
			self.cKatu,
			self.cGeki,
			self.fullCombo,
			self.mods,
			self.playerUserID,
			self.rank,
			self.date)

	def setCompletedStatus(self):
		"""
		Set this score completed status and rankedScoreIncrease
		"""
		b = beatmap.beatmap(self.fileMd5, 0)
		if not scoreUtils.isRankable(self.mods):
			log.debug("Unrankable mods")
			return

		self.completed = 0
		if self.passed:
			# Get userID
			userID = userUtils.getID(self.playerName)

			# No duplicates found.
			# Get right "completed" value
			personalBest = glob.db.fetch("SELECT id, score, pp FROM scores WHERE userid = %s AND beatmap_md5 = %s AND play_mode = %s AND completed = 3 LIMIT 1", [userID, self.fileMd5, self.gameMode])
			if personalBest is None:
				# This is our first score on this map, so it's our best score
				self.completed = 3
				self.rankedScoreIncrease = self.score
				self.oldPersonalBest = 0
				self.personalOldBestScore = None
			else:
				self.personalOldBestScore = personalBest["id"]
				# Compare personal best's score with current score
				# idk but my version is not work or something goes wrong ;d
				is_pp_over_score = kotrikhelper.isPPOverScore(userID)
				if b.rankedStatus in [rankedStatuses.RANKED, rankedStatuses.APPROVED, rankedStatuses.QUALIFIED]:
					if is_pp_over_score:
						if self.pp > personalBest["pp"]:
							# New best score
							self.completed = 3
							self.rankedScoreIncrease = self.score-personalBest["score"]
							self.oldPersonalBest = personalBest["id"]
						else:
							self.completed = 2
							self.rankedScoreIncrease = 0
							self.oldPersonalBest = 0
					else:
						if self.score > personalBest["score"]:
							# New best score
							self.completed = 3
							self.rankedScoreIncrease = self.score-personalBest["score"]
							self.oldPersonalBest = personalBest["id"]
						else:
							self.completed = 2
							self.rankedScoreIncrease = 0
							self.oldPersonalBest = 0
				elif b.rankedStatus == rankedStatuses.LOVED:
					if self.score > personalBest["score"]:
						# New best score
						self.completed = 3
						self.rankedScoreIncrease = self.score-personalBest["score"]
						self.oldPersonalBest = personalBest["id"]
					else:
						self.completed = 2
						self.rankedScoreIncrease = 0
						self.oldPersonalBest = 0
		elif self.quit:
			log.debug("QUIT")
			self.completed = 0
		elif self.failed:
			log.debug("FAILED")
			self.completed = 1

		log.debug("Completed status: {}".format(self.completed))

	def saveScoreInDB(self):
		"""
		Save this score in DB (if passed and mods are valid)
		"""
		# Add this score
		if self.completed >= 0:
			query = "INSERT INTO scores (id, beatmap_md5, userid, score, max_combo, full_combo, mods, 300_count, 100_count, 50_count, katus_count, gekis_count, misses_count, time, play_mode, completed, accuracy, pp, playtime) VALUES (NULL, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);"
			self.scoreID = int(glob.db.execute(query, [self.fileMd5, userUtils.getID(self.playerName), self.score, self.maxCombo, int(self.fullCombo), self.mods, self.c300, self.c100, self.c50, self.cKatu, self.cGeki, self.cMiss, self.playDateTime, self.gameMode, self.completed, self.accuracy * 100, self.pp, self.playTime]))

			#glob.db.execute("INSERT INTO scores_hashes (score_id, hash) VALUES (%s, %s)", [
			#	self.scoreID,
			#	self.scoreHash
			#])

			# Redis stats
			glob.redis.incr("ripple:submitted_scores")
			# Set old personal best to completed = 2
			if self.oldPersonalBest > 0:
				glob.db.execute("UPDATE scores SET completed = 2 WHERE id = %s", [self.oldPersonalBest])

	def calculatePP(self, b = None):
		"""
		Calculate this score's pp value if completed == 3
		"""
		# Create beatmap object
		if b is None:
			b = beatmap.beatmap(self.fileMd5, 0)

		# Calculate pp
		if b.is_rankable and scoreUtils.isRankable(self.mods) and self.passed:
			# RX, AP only 0(std)
			if (self.mods&PlayMods.RELAX) or (self.mods&PlayMods.RELAX2):
				if self.gameMode in pp.PP_RELAX_CALCULATORS:
					calculator = pp.PP_RELAX_CALCULATORS[self.gameMode](b, self)
					self.pp = calculator.pp
					self.sr = calculator.stars
					return
				else:
					self.pp = 0
					return

			if self.gameMode in pp.PP_CALCULATORS:
				calculator = pp.PP_CALCULATORS[self.gameMode](b, self)
				self.pp = calculator.pp
				self.sr = calculator.stars
				return
		else:
			self.pp = 0

class PerfectScoreFactory:
	@staticmethod
	def create(beatmap, game_mode=gameModes.STD):
		"""
		Factory method that creates a perfect score.
		Used to calculate max pp amount for a specific beatmap.
		:param beatmap: beatmap object
		:param game_mode: game mode number. Default: `gameModes.STD`
		:return: `score` object
		"""
		s = score()
		s.accuracy = 1.
		# max combo cli param/arg gets omitted if it's < 0 and oppai/catch-the-pp set it to max combo.
		# maniapp ignores max combo entirely.
		s.maxCombo = -1
		s.fullCombo = True
		s.passed = True
		s.gameMode = game_mode
		if s.gameMode == gameModes.MANIA:
			s.score = 1000000
		return s
