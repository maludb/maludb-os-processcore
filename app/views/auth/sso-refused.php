<?php /** @var string $launcher */ ?>
<div class="text-center" id="sso-refused">
    <h4 class="mb-3">This sign-on link has expired</h4>
    <p class="text-muted">Open ProcessCore from the launcher again.</p>
    <?php if ($launcher !== ''): ?><a class="btn btn-primary" id="sso-refused-launcher" href="<?= e($launcher) ?>">Back to the launcher</a><?php endif; ?>
</div>
