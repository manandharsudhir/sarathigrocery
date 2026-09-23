enum OrderStatus { placed, confirmed, preparing, ready, outForDelivery, delivered, cancelled }

/// The happy-path lifecycle, in order. [OrderStatus.cancelled] is deliberately
/// absent — it's an exit from any stage, not a stage of its own.
const List<OrderStatus> orderLifecycle = [
  OrderStatus.placed,
  OrderStatus.confirmed,
  OrderStatus.preparing,
  OrderStatus.ready,
  OrderStatus.outForDelivery,
  OrderStatus.delivered,
];

/// The stage after [current], or null if the order is finished or cancelled.
OrderStatus? nextOrderStatus(OrderStatus current) {
  final index = orderLifecycle.indexOf(current);
  if (index == -1 || index + 1 >= orderLifecycle.length) return null;
  return orderLifecycle[index + 1];
}

String orderStatusLabel(OrderStatus status) {
  switch (status) {
    case OrderStatus.placed:
      return 'Placed';
    case OrderStatus.confirmed:
      return 'Confirmed';
    case OrderStatus.preparing:
      return 'Preparing';
    case OrderStatus.ready:
      return 'Ready';
    case OrderStatus.outForDelivery:
      return 'Out for Delivery';
    case OrderStatus.delivered:
      return 'Delivered';
    case OrderStatus.cancelled:
      return 'Cancelled';
  }
}
