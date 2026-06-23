from loguru import logger


def invariant_log(condition: bool, success_message: str, failure_message: str):
    if not condition:
        logger.error(failure_message)
        # raise ValueError(failure_message)
    logger.success(success_message)
