CREATE TABLE IF NOT EXISTS `onlinetime` (
  `client_id` int(11) unsigned NOT NULL,
  `client_unique_identifier` varchar(40) NOT NULL,
  `onlinetime` bigint(11) unsigned NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
ALTER TABLE `onlinetime` ADD UNIQUE KEY `client_id` (`client_id`);

ALTER TABLE `onlinetime` ADD `nickname` VARCHAR(128) NOT NULL AFTER `client_unique_identifier`;
ALTER TABLE `onlinetime` CHANGE `nickname` `nickname` VARCHAR(128) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL;
