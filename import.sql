SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";

CREATE TABLE IF NOT EXISTS `onlinetime` (
  `client_id` int(11) unsigned NOT NULL,
  `client_unique_identifier` varchar(40) NOT NULL,
  `nickname` varchar(128) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  `onlinetime` bigint(11) unsigned NOT NULL,
  `connectioncount` int(10) unsigned NOT NULL DEFAULT '1',
  `lastupdate` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00' ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
ALTER TABLE `onlinetime` ADD UNIQUE KEY `client_id` (`client_id`);

CREATE TABLE IF NOT EXISTS `onlineclients` (
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `clients` smallint(5) unsigned NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
ALTER TABLE `onlineclients` ADD UNIQUE(`time`);
