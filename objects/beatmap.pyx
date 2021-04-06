import time

from common.log import logUtils as log
from constants import rankedStatuses
from helpers import osuapiHelper
from objects import glob
from common.web import cheesegull
from urllib.parse import unquote
from re import compile as rcomp

MAPFILE_REGEX = rcomp(r'^(?P<artist>.+) - (?P<title>.+) \((?P<creator>.+)\) \[(?P<version>.+)\]\.osu$')  # I think we both know where this is coming from)

class beatmap:
	__slots__ = ["songName", "fileMD5", "rankedStatus", "rankedStatusFrozen", "beatmapID", "beatmapSetID", "offset",
	             "rating", "starsStd", "starsTaiko", "starsCtb", "starsMania", "AR", "OD", "maxCombo", "hitLength",
	             "bpm", "playcount" ,"passcount", "refresh", "approvedDate", "totalLength"]

	def __init__(self, md5 = None, beatmapSetID = None, gameMode = 0, refresh=False, file_name: str = None):
		"""
		Initialize a beatmap object.

		md5 -- beatmap md5. Optional.
		beatmapSetID -- beatmapSetID. Optional.
		"""
		self.songName = ""
		self.fileMD5 = ""
		self.rankedStatus = rankedStatuses.NOT_SUBMITTED
		self.rankedStatusFrozen = 0
		self.beatmapID = 0
		self.beatmapSetID = 0
		self.offset = 0		# Won't implement
		self.rating = 10.0 	# Won't implement

		self.starsStd = 0.0	# stars for converted
		self.starsTaiko = 0.0	# stars for converted
		self.starsCtb = 0.0		# stars for converted
		self.starsMania = 0.0	# stars for converted
		self.AR = 0.0
		self.OD = 0.0
		self.maxCombo = 0
		self.hitLength = 0
		self.totalLength = 0
		self.bpm = 0
		self.approvedDate = None

		# Statistics for ranking panel
		self.playcount = 0

		# Force refresh from osu api
		self.refresh = refresh

		if md5 and beatmapSetID:
			self.setData(md5, beatmapSetID, file_name)

	def addBeatmapToDB(self):
		"""
		Add current beatmap data in db if not in yet
		"""
		# Make sure the beatmap is not already in db
		bdata = glob.db.fetch("SELECT id, ranked_status_freezed, ranked FROM beatmaps WHERE beatmap_md5 = %s OR beatmap_id = %s LIMIT 1", [self.fileMD5, self.beatmapID])
		if bdata is not None:
			# This beatmap is already in db, remove old record
			# Get current frozen status
			frozen = bdata["ranked_status_freezed"]
			if frozen == 1:
				self.rankedStatus = bdata["ranked"]
			log.debug("Deleting old beatmap data ({})".format(bdata["id"]))
			glob.db.execute("DELETE FROM beatmaps WHERE id = %s LIMIT 1", [bdata["id"]])
		else:
			# Unfreeze beatmap status
			frozen = 0

		# Add new beatmap data
		log.debug("Saving beatmap data in db...")
		glob.db.execute("INSERT INTO `beatmaps` (`id`, `beatmap_id`, `beatmapset_id`, `beatmap_md5`, `song_name`, `ar`, `od`, `difficulty_std`, `difficulty_taiko`, `difficulty_ctb`, `difficulty_mania`, `max_combo`, `hit_length`, `bpm`, `ranked`, `latest_update`, `ranked_status_freezed`) VALUES (NULL, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);", [
			self.beatmapID,
			self.beatmapSetID,
			self.fileMD5,
			self.songName.encode("utf-8", "ignore").decode("utf-8"),
			self.AR,
			self.OD,
			self.starsStd,
			self.starsTaiko,
			self.starsCtb,
			self.starsMania,
			self.maxCombo,
			self.hitLength,
			self.bpm,
			self.rankedStatus,
			int(time.time()),
			frozen
		])

	def setDataFromDB(self, md5, song_name: str = None):
		"""
		Set this object's beatmap data from db.

		md5 -- beatmap md5
		return -- True if set, False if not set
		"""
		# Get data from DB
		if song_name:
			data = glob.db.fetch("SELECT * FROM beatmaps WHERE song_name LIKE %s", [
				song_name
			])
		else:
			data = glob.db.fetch("SELECT * FROM beatmaps WHERE beatmap_md5 = %s LIMIT 1", [md5])

		# Make sure the query returned something
		if data is None:
			return False

		# Make sure the beatmap is not an old one
		if data["difficulty_taiko"] == 0 and data["difficulty_ctb"] == 0 and data["difficulty_mania"] == 0:
			log.debug("Difficulty for non-std gamemodes not found in DB, refreshing data from osu!api...")
			return False

		# Set cached data period
		expire = int(glob.conf.config["server"]["beatmapcacheexpire"])

		# If the beatmap is ranked, we don't need to refresh data from osu!api that often
		if data["ranked"] >= rankedStatuses.RANKED and data["ranked_status_freezed"] == 0:
			expire *= 3

		# Make sure the beatmap data in db is not too old
		if int(expire) > 0 and time.time() > data["latest_update"]+int(expire):
			if data["ranked_status_freezed"] == 1:
				self.setDataFromDict(data)
			return False

		# Data in DB, set beatmap data
		log.debug("Got beatmap data from db")
		self.setDataFromDict(data)			
		return True

	def setAdditionalInfo(self):
		#And finally we need approvedDate, totalLength, cheesegull plz help
		cg_request = cheesegull.getBeatmapSet(self.beatmapSetID)
		if cg_request:
			# I consider it quite possible
			# I'll be safe just in case
			if self.approvedDate == "":
				self.approvedDate = cg_request.get('ApprovedDate', '')

			if self.totalLength == 0: # just it can be > 0 when it get info from osu!API 
				for bm in cg_request.get('ChildrenBeatmaps', []):
					if bm['BeatmapID'] == self.beatmapID:
						self.totalLength = bm['TotalLength']
						break
		
		return True

	def setDataFromDict(self, data):
		"""
		Set this object's beatmap data from data dictionary.

		data -- data dictionary
		return -- True if set, False if not set
		"""
		self.songName = data["song_name"]
		self.fileMD5 = data["beatmap_md5"]
		self.rankedStatus = int(data["ranked"])
		self.rankedStatusFrozen = int(data["ranked_status_freezed"])
		self.beatmapID = int(data["beatmap_id"])
		self.beatmapSetID = int(data["beatmapset_id"])
		self.AR = float(data["ar"])
		self.OD = float(data["od"])
		self.starsStd = float(data["difficulty_std"])
		self.starsTaiko = float(data["difficulty_taiko"])
		self.starsCtb = float(data["difficulty_ctb"])
		self.starsMania = float(data["difficulty_mania"])
		self.maxCombo = int(data["max_combo"])
		self.hitLength = int(data["hit_length"])
		self.bpm = int(data["bpm"])
		# Ranking panel statistics
		self.playcount = int(data["playcount"]) if "playcount" in data else 0
		self.passcount = int(data["passcount"]) if "passcount" in data else 0

		self.setAdditionalInfo()

	def setDataFromOsuApi(self, md5, beatmapSetID):
		"""
		Set this object's beatmap data from osu!api.

		md5 -- beatmap md5
		beatmapSetID -- beatmap set ID, used to check if a map is outdated
		return -- True if set, False if not set
		"""
		# Check if osuapi is enabled
		mainData = None
		dataStd = osuapiHelper.osuApiRequest("get_beatmaps", "h={}&a=1&m=0".format(md5))
		dataTaiko = osuapiHelper.osuApiRequest("get_beatmaps", "h={}&a=1&m=1".format(md5))
		dataCtb = osuapiHelper.osuApiRequest("get_beatmaps", "h={}&a=1&m=2".format(md5))
		dataMania = osuapiHelper.osuApiRequest("get_beatmaps", "h={}&a=1&m=3".format(md5))
		if dataStd is not None:
			mainData = dataStd
		elif dataTaiko is not None:
			mainData = dataTaiko
		elif dataCtb is not None:
			mainData = dataCtb
		elif dataMania is not None:
			mainData = dataMania

		# If the beatmap is frozen and still valid from osu!api, return True so we don't overwrite anything
		if mainData is not None and self.rankedStatusFrozen == 1:
			return True

		if type(mainData) is not dict:
			return False

		# We have data from osu!api, set beatmap data
		log.debug("Got beatmap data from osu!api")
		self.songName = "{} - {} [{}]".format(mainData["artist"], mainData["title"], mainData["version"])
		self.fileMD5 = md5
		self.rankedStatus = convertRankedStatus(int(mainData["approved"]))
		self.beatmapID = int(mainData["beatmap_id"])
		self.beatmapSetID = int(mainData["beatmapset_id"])
		self.AR = float(mainData["diff_approach"])
		self.OD = float(mainData["diff_overall"])

		# Determine stars for every mode
		self.starsStd = 0
		self.starsTaiko = 0
		self.starsCtb = 0
		self.starsMania = 0

		# Some strange about peppy!Api and CTB
		if dataStd and dataStd.get("difficultyrating", False):
			self.starsStd = dataStd["difficultyrating"]

		if dataTaiko and dataTaiko.get("difficultyrating", False):
			self.starsTaiko = dataTaiko["difficultyrating"]

		if dataCtb and dataCtb.get("diff_aim", False):
			self.starsCtb = dataCtb["diff_aim"]

		if dataMania and dataMania.get("difficultyrating", False):
			self.starsMania = dataMania["difficultyrating"]

		self.maxCombo = int(mainData["max_combo"]) if mainData["max_combo"] is not None else 0
		self.hitLength = int(mainData["hit_length"])
		self.totalLength = int(mainData["total_length"])
		if mainData["bpm"] is not None:
			self.bpm = int(float(mainData["bpm"]))
		else:
			self.bpm = -1

		self.setAdditionalInfo()
		return True

	def setData(self, md5, beatmapSetID, fileName: str = None):
		"""
		Set this object's beatmap data from highest level possible.

		md5 -- beatmap MD5
		beatmapSetID -- beatmap set ID
		"""
		# Get beatmap from db
		dbResult = self.setDataFromDB(md5)

		# Force refresh from osu api.
		# We get data before to keep frozen maps ranked
		# if they haven't been updated
		if dbResult == True and self.refresh:
			dbResult = False

		if not dbResult:
			log.debug("Beatmap not found in db")
			# If this beatmap is not in db, get it from osu!api
			apiResult = self.setDataFromOsuApi(md5, beatmapSetID)
			if not apiResult:
				if fileName:
					# available only for osu-osz2-getscores.php
					fileName = unquote(fileName.replace("+", ' '))

					re = MAPFILE_REGEX.match(fileName)		
					if not re:
						self.rankedStatus = rankedStatuses.NOT_SUBMITTED
						return

					# Gives another try with setDataFromDB but now with song_name!
					DBresult2 = self.setDataFromDB(None, f"{re['artist']}%{re['title']}%[{re['version']}]")
					if not DBresult2:
						self.rankedStatus = rankedStatuses.NOT_SUBMITTED
					else:
						if self.fileMD5 != md5:
							self.rankedStatus = rankedStatuses.NEED_UPDATE
				else:
					self.rankedStatus = rankedStatuses.NOT_SUBMITTED

			elif self.rankedStatus != rankedStatuses.NOT_SUBMITTED and self.rankedStatus != rankedStatuses.NEED_UPDATE:
				# We get beatmap data from osu!api, save it in db
				self.addBeatmapToDB()
		else:
			log.debug("Beatmap found in db")

		log.debug("{}\n{}\n{}\n{}".format(self.starsStd, self.starsTaiko, self.starsCtb, self.starsMania))

	def getData(self, totalScores=0, version=4):
		"""
		Return this beatmap's data (header) for getscores
		return -- beatmap header for getscores
		"""
		rankedStatusOutput = self.rankedStatus

		# Fix loved maps for old clients
		if version < 4 and self.rankedStatus == rankedStatuses.LOVED:
			rankedStatusOutput = rankedStatuses.QUALIFIED

		data = "{}|false".format(rankedStatusOutput)
		if self.rankedStatus != rankedStatuses.NOT_SUBMITTED and self.rankedStatus != rankedStatuses.NEED_UPDATE and self.rankedStatus != rankedStatuses.UNKNOWN:
			# If the beatmap is updated and exists, the client needs more data
			data += "|{}|{}|{}\n{}\n{}\n{}\n".format(self.beatmapID, self.beatmapSetID, totalScores, self.offset, self.songName, self.rating)

		# Return the header
		return data

	def getCachedTillerinoPP(self):
		"""
		Returned cached pp values for 100, 99, 98 and 95 acc nomod
		(used ONLY with Tillerino, pp is always calculated with oppai when submitting scores)

		return -- list with pp values. [0,0,0,0] if not cached.
		"""
		data = glob.db.fetch("SELECT pp_100, pp_99, pp_98, pp_95 FROM beatmaps WHERE beatmap_md5 = %s LIMIT 1", [self.fileMD5])
		if data is None:
			return [0,0,0,0]
		return [data["pp_100"], data["pp_99"], data["pp_98"], data["pp_95"]]

	def saveCachedTillerinoPP(self, l):
		"""
		Save cached pp for tillerino

		l -- list with 4 default pp values ([100,99,98,95])
		"""
		glob.db.execute("UPDATE beatmaps SET pp_100 = %s, pp_99 = %s, pp_98 = %s, pp_95 = %s WHERE beatmap_md5 = %s", [l[0], l[1], l[2], l[3], self.fileMD5])

	@property
	def is_rankable(self):
		return self.rankedStatus >= rankedStatuses.RANKED and self.rankedStatus != rankedStatuses.UNKNOWN

def convertRankedStatus(approvedStatus):
	"""
	Convert approved_status (from osu!api) to ranked status (for getscores)

	approvedStatus -- approved status, from osu!api
	return -- rankedStatus for getscores
	"""
	approvedStatus = int(approvedStatus)
	if approvedStatus <= 0:
		return rankedStatuses.PENDING
	elif approvedStatus == 1:
		return rankedStatuses.RANKED
	elif approvedStatus == 2:
		return rankedStatuses.APPROVED
	elif approvedStatus == 3:
		return rankedStatuses.QUALIFIED
	elif approvedStatus >= 4:
		return rankedStatuses.LOVED
	else:
		return rankedStatuses.UNKNOWN

def incrementPlaycount(md5, passed):
	"""
	Increment playcount (and passcount) for a beatmap

	md5 -- beatmap md5
	passed -- if True, increment passcount too
	"""
	glob.db.execute("UPDATE beatmaps SET playcount = playcount+1 WHERE beatmap_md5 = %s LIMIT 1", [md5])
	if passed:
		glob.db.execute("UPDATE beatmaps SET passcount = passcount+1 WHERE beatmap_md5 = %s LIMIT 1", [md5])
