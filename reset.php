<?php

/**
 * Reset all visits.
 * /!\ TOTALLY UNSAFE, use only for dev.
 */

if (!defined('PIWIK_DOCUMENT_ROOT')) {
    define('PIWIK_DOCUMENT_ROOT', dirname(__FILE__) == '/' ? '' : dirname(__FILE__));
}
if (file_exists(PIWIK_DOCUMENT_ROOT . '/bootstrap.php')) {
    require_once PIWIK_DOCUMENT_ROOT . '/bootstrap.php';
}
if (!defined('PIWIK_INCLUDE_PATH')) {
    define('PIWIK_INCLUDE_PATH', PIWIK_DOCUMENT_ROOT);
}

require_once PIWIK_INCLUDE_PATH . '/core/bootstrap.php';

use Piwik\DataAccess\RawLogDao;
use Piwik\LogDeleter;
use Piwik\Container\StaticContainer;
use Piwik\FrontController;

use Piwik\Db;
use Piwik\Common;

FrontController::setUpSafeMode();
$environment = new \Piwik\Application\Environment(null);
try {
        $environment->init();
} catch(\Exception $e) {}

$controller = FrontController::getInstance();
$controller->init();

$logDeleter = StaticContainer::get('Piwik\LogDeleter');
$rawLogDao = StaticContainer::get('Piwik\DataAccess\RawLogDao');

$logDeleter->deleteVisitsFor(null, null, 1);
$logDeleter->deleteVisitsFor(null, null, 2);

print('OK');
