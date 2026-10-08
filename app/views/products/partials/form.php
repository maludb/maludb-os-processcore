<?php /** @var array $product  @var array $errors */
$id = $product['id'] ?? null;
$isEdit = $id !== null;
$title = $isEdit ? 'Edit ' . ($product['name'] ?? 'Product') : 'Add Product';
$cancelUrl = $isEdit ? '/products/' . $id : '/products/';
$p = 'product-form';
?>
<?= view('shared/page-header.php', ['title' => $title, 'screen' => 'product-form', 'crumbs' => ['Products' => null, 'Products and recipes' => '/products/', $isEdit ? 'Edit' : 'Add' => null], 'actionsHtml' => form_actions('product-form', $cancelUrl, 'Save Product')]) ?>
<div class="main-content" id="product-form-content">
    <form id="product-form" method="post" action="/products/save" hx-post="/products/save" hx-target="#page-content" hx-swap="innerHTML">
        <?= csrf_field() ?>
        <?php if ($isEdit): ?><input type="hidden" name="id" value="<?= e($id) ?>" /><?php endif; ?>
        <div class="row"><div class="col-lg-12">
            <div class="card" id="product-form-card">
                <div class="card-body">
                    <div class="mb-4"><h5 class="fw-bold mb-0 me-4"><span class="d-block mb-2">Product</span><span class="fs-12 fw-normal text-muted text-truncate-1-line">What ProcessCore makes. Recipes, packaging, specs and approvals hang off the product.</span></h5></div>
                    <?= view('shared/validation-errors.php', ['errors' => array_values($errors), 'id' => 'product-form-errors']) ?>
                    <?= form_input($p, 'code', 'Code', $product['code'] ?? '', $errors, ['required' => true, 'maxlength' => 40, 'icon' => 'feather-hash', 'autofocus' => !$isEdit]) ?>
                    <?= form_input($p, 'name', 'Name', $product['name'] ?? '', $errors, ['required' => true, 'maxlength' => 120, 'icon' => 'feather-book-open']) ?>
                    <?= form_select($p, 'beverage_type', 'Beverage', PRODUCT_BEVERAGES, $product['beverage_type'] ?? 'cider', $errors, ['required' => true]) ?>
                    <?= form_input($p, 'style', 'Style', $product['style'] ?? '', $errors, ['maxlength' => 120, 'icon' => 'feather-tag']) ?>
                    <?= form_select($p, 'intended_tax_class', 'Intended tax class', PRODUCT_TAX_CLASSES, $product['intended_tax_class'] ?? 'hard_cider', $errors, ['required' => true]) ?>
                    <?= form_input($p, 'target_abv', 'Target ABV (%)', $product['target_abv'] ?? '', $errors, ['type' => 'number', 'min' => 0, 'max' => 25, 'step' => '0.01', 'icon' => 'feather-percent']) ?>
                    <?= form_input($p, 'target_fruit_share', 'Target fruit share (%)', $product['target_fruit_share_pct'] ?? '100', $errors, ['type' => 'number', 'min' => 0, 'max' => 100, 'step' => '0.01', 'icon' => 'feather-percent', 'name' => 'target_fruit_share_pct']) ?>
                    <?= form_checkbox($p, 'contains_other_fruit', 'Contains fruit other than apple or pear', (bool) ($product['contains_other_fruit'] ?? false)) ?>
                    <?= form_checkbox($p, 'contains_flavoring', 'Contains flavoring beyond the hard-cider allowance', (bool) ($product['contains_flavoring'] ?? false)) ?>
                    <?= form_select($p, 'status', 'Status', PRODUCT_STATUSES, $product['status'] ?? 'draft', $errors, ['required' => true]) ?>
                    <?= form_textarea($p, 'notes', 'Notes', $product['notes'] ?? '', $errors, ['last' => true]) ?>
                </div>
            </div>
        </div></div>
    </form>
</div>
