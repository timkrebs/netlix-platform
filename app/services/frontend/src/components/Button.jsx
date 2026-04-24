import React from 'react';

const VARIANT_CLASS = {
  primary: 't-btn-primary',
  ghost: 't-btn-ghost',
  add: 't-add',
  cart: 't-cart-btn',
  icon: 't-icon-btn',
  link: 't-link',
  sizeChip: 't-size-chip',
};

export default function Button({
  variant = 'primary',
  className = '',
  type = 'button',
  children,
  ...rest
}) {
  const variantClass = VARIANT_CLASS[variant] || '';
  const cls = [variantClass, className].filter(Boolean).join(' ');
  return (
    <button type={type} className={cls} {...rest}>
      {children}
    </button>
  );
}
