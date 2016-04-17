SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";

DROP TABLE IF EXISTS `ts3bot_info`;
CREATE TABLE IF NOT EXISTS `ts3bot_info` (
  `uuid` varchar(64) NOT NULL,
  `forum_uuid` int(10) unsigned DEFAULT NULL,
  `nickname` varchar(128) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  `type` varchar(16) DEFAULT NULL,
  `hash` varchar(64) DEFAULT NULL,
  `onlinetime` bigint(20) unsigned NOT NULL DEFAULT '0',
  `onlinecount` int(10) unsigned NOT NULL DEFAULT '0',
  `created` timestamp NULL DEFAULT NULL,
  `lastupdate` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00' ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `ts3bot_kick`;
CREATE TABLE IF NOT EXISTS `ts3bot_kick` (
  `id` int(10) unsigned NOT NULL,
  `uuid` varchar(40) NOT NULL,
  `nickname` varchar(128) NOT NULL,
  `onlinetime` bigint(20) unsigned NOT NULL,
  `reasonid` tinyint(3) unsigned NOT NULL,
  `reasonmsg` varchar(128) CHARACTER SET utf8 COLLATE utf8_swedish_ci DEFAULT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=latin1;


ALTER TABLE `ts3bot_info`
  ADD PRIMARY KEY (`uuid`);

ALTER TABLE `ts3bot_kick`
  ADD PRIMARY KEY (`id`), ADD KEY `client_unique_identifier` (`uuid`);


ALTER TABLE `ts3bot_kick`
  MODIFY `id` int(10) unsigned NOT NULL AUTO_INCREMENT;
